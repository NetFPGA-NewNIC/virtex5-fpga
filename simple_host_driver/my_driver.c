/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        my_driver.c
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Simple device driver
*
*
*    This code is initially developed for the Network-as-a-Service (NaaS) project.
*
*  Copyright notice:
*        Copyright (C) 2014 University of Cambridge
*
*  Licence:
*        This file is part of the NetFPGA 10G development base package.
*
*        This file is free code: you can redistribute it and/or modify it under
*        the terms of the GNU Lesser General Public License version 2.1 as
*        published by the Free Software Foundation.
*
*        This package is distributed in the hope that it will be useful, but
*        WITHOUT ANY WARRANTY; without even the implied warranty of
*        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
*        Lesser General Public License for more details.
*
*        You should have received a copy of the GNU Lesser General Public
*        License along with the NetFPGA source package.  If not, see
*        http://www.gnu.org/licenses/.
*
*/

#include <linux/module.h>       /* Needed by all modules */
#include <linux/kernel.h>       /* Needed for KERN_INFO */
#include <linux/init.h>         /* Needed for the macros */
#include <linux/types.h>        /* Needed for the macros */
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/delay.h> 
#include <linux/spinlock.h> 
#include <asm/cacheflush.h>
#include <linux/etherdevice.h>
#include "my_driver.h"

MODULE_LICENSE("Dual BSD/GPL");
MODULE_AUTHOR("Cambridge NaaS Team");
MODULE_DESCRIPTION("A simple approach");	/* What does this module do */

static DEFINE_SPINLOCK(rx_subsys);

static struct pci_device_id pci_id[] = {
    {PCI_DEVICE(XILINX_VENDOR_ID, MY_APPLICATION_ID)},
    {0}
};
MODULE_DEVICE_TABLE(pci, pci_id);

void rx_wq_function(struct work_struct *wk)
{
    struct my_driver_host_data *my_drv_data = ((struct my_work_t *)wk)->my_drv_data_ptr;
    struct sk_buff *my_skb;
    u32 *current_hp_addr;
    volatile u32 current_pkt_len;
    volatile u32 next_pkt_len;
    u32 next_pkt_dw_index;
    volatile u64 huge_page_status;
    u32 timeout;
    unsigned long flags;
    u32 polling_counter;

    spin_lock_irqsave(&rx_subsys, flags);

    polling_counter = 0;
    init:
    if (polling_counter == 0xffff)
    {
        printk(KERN_INFO "Myd: no pkts. exit polling. enable interrupts\n");
        *(((u32 *)my_drv_data->bar2) + 8) = 0xcacabeef; // enable interrupts
        spin_unlock_irqrestore(&rx_subsys, flags);
        return;
    }

    if (!my_drv_data->huge_page_index)
        current_hp_addr = (u32 *)my_drv_data->huge_page_kern_address1;
    else
        current_hp_addr = (u32 *)my_drv_data->huge_page_kern_address2;
    
    next_pkt:
    if (my_drv_data->current_pkt_dw_index < (2*1024*1024/4))
    {
        timeout = 0;
        do {
            
            current_pkt_len = current_hp_addr[my_drv_data->current_pkt_dw_index+1];
            if (current_pkt_len)
                goto alloc_my_skb;

            timeout++;
        } while (timeout < 1000);

        huge_page_status = *((u64 *)current_hp_addr);            //QW0 contains this information
        if ( (((u32)huge_page_status) << 1) > (my_drv_data->current_pkt_dw_index - 32) )
        {
            printk(KERN_ERR "Myd: invalid current_pkt_len\n");
            spin_unlock_irqrestore(&rx_subsys, flags);
            return;
        }
        if ((huge_page_status >> 32) & 0x1)                             // check if hp was closed
            goto close_hp;

        polling_counter++;
        goto init;
        
        alloc_my_skb:
        polling_counter = 0;
        if (current_pkt_len > 1514)
        {
            printk(KERN_ERR "Myd: invalid current_pkt_len\n");
            spin_unlock_irqrestore(&rx_subsys, flags);
            return;
        }

        my_skb = netdev_alloc_skb(my_drv_data->my_net_device, current_pkt_len);
        if (!my_skb)
        {
            printk(KERN_ERR "Myd: failed netdev_alloc_skb: current_pkt_len = %d\n", current_pkt_len);
            spin_unlock_irqrestore(&rx_subsys, flags);
            return;
        }
        skb_reserve(my_skb, NET_IP_ALIGN);

        next_pkt_dw_index = my_drv_data->current_pkt_dw_index + (__ALIGN_KERNEL_MASK(current_pkt_len, 0x7) >> 2) + 2;

        if (next_pkt_dw_index > (2*1024*1024/4))
        {
            printk(KERN_ERR "Myd: Something happend and I received an overwritten huge page\n");
            dev_kfree_skb(my_skb);
            spin_unlock_irqrestore(&rx_subsys, flags);
            return;
        }

        timeout = 0;
        do {
            next_pkt_len = current_hp_addr[next_pkt_dw_index+1];
            
            if (next_pkt_len)
                goto eat_pkt;

            huge_page_status = *((u64 *)current_hp_addr);            //QW0 contains this information
            if ( (((u32)huge_page_status) << 1) > (my_drv_data->current_pkt_dw_index - 32) )
            {
                if ( (((u32)huge_page_status) << 1) == (my_drv_data->current_pkt_dw_index - 32 + (__ALIGN_KERNEL_MASK(current_pkt_len, 0x7) >> 2) + 2) )
                {
                    if ((huge_page_status >> 32) & 0x1)                             // check if hp was closed
                        goto eat_pkt_close_hp;
                    else
                    {
                        next_pkt_dw_index = __ALIGN_KERNEL_MASK(next_pkt_dw_index, 0x1f);
                        goto eat_pkt;
                    }
                }
                else if ( (((u32)huge_page_status) << 1) < (my_drv_data->current_pkt_dw_index - 32 + (__ALIGN_KERNEL_MASK(current_pkt_len, 0x7) >> 2) + 2) )
                {
                    printk(KERN_ERR "Myd: invalid current_pkt_len\n");
                    spin_unlock_irqrestore(&rx_subsys, flags);
                    return;
                }
            }

            timeout++;
        } while (timeout < 100000);

        printk(KERN_ERR "Myd: invalid current_pkt_len\n");
        spin_unlock_irqrestore(&rx_subsys, flags);
        return; 

        eat_pkt:
        memcpy(my_skb->data, (void *)(current_hp_addr + my_drv_data->current_pkt_dw_index + 2), current_pkt_len);
        skb_put(my_skb, current_pkt_len);
        my_skb->protocol = eth_type_trans(my_skb, my_drv_data->my_net_device);
        my_skb->ip_summed = CHECKSUM_NONE;
        netif_receive_skb(my_skb);
        my_drv_data->my_net_device->stats.rx_packets++;
        memset((void *)(current_hp_addr + my_drv_data->current_pkt_dw_index), 0, __ALIGN_KERNEL_MASK(current_pkt_len, 0x7) + 8);         // this will be implemented in the memory's sense amplifiers (destructive readout memories)

        my_drv_data->current_pkt_dw_index = next_pkt_dw_index;
        goto next_pkt;

        eat_pkt_close_hp:
        memcpy(my_skb->data, (void *)(current_hp_addr + my_drv_data->current_pkt_dw_index + 2), current_pkt_len);
        skb_put(my_skb, current_pkt_len);
        my_skb->protocol = eth_type_trans(my_skb, my_drv_data->my_net_device);
        my_skb->ip_summed = CHECKSUM_NONE;
        netif_receive_skb(my_skb);
        my_drv_data->my_net_device->stats.rx_packets++;
        memset((void *)(current_hp_addr + my_drv_data->current_pkt_dw_index), 0, __ALIGN_KERNEL_MASK(current_pkt_len, 0x7) + 8);         // this will be implemented in the memory's sense amplifiers (destructive readout memories)

        close_hp:
        memset((void *)current_hp_addr, 0, 8);
        my_drv_data->current_pkt_dw_index = 32;
        if (!my_drv_data->huge_page_index)
        {
            my_drv_data->huge_page_index = 1;
            *(((u32 *)my_drv_data->bar2) + 24) = 0xcacabeef;
        }
        else
        {
            my_drv_data->huge_page_index = 0;
            *(((u32 *)my_drv_data->bar2) + 25) = 0xcacabeef;
        }
        polling_counter = 0;
        goto init;
    }
    else if (my_drv_data->current_pkt_dw_index > (2*1024*1024/4))
    {
        printk(KERN_ERR "Myd: Something happend and I received an overwritten huge page\n");
        spin_unlock_irqrestore(&rx_subsys, flags);
        return;
    }
    else
    {
        huge_page_status = *((u64 *)current_hp_addr);            //QW0 contains this information
        if ((huge_page_status >> 32) & 0x1)                             // check if hp was closed
        {
            memset((void *)current_hp_addr, 0, 8);
            my_drv_data->current_pkt_dw_index = 32;
            if (!my_drv_data->huge_page_index)
            {
                my_drv_data->huge_page_index = 1;
                *(((u32 *)my_drv_data->bar2) + 24) = 0xcacabeef;
            }
            else
            {
                my_drv_data->huge_page_index = 0;
                *(((u32 *)my_drv_data->bar2) + 25) = 0xcacabeef;
            }
        }
        else
        {
            printk(KERN_ERR "Myd: Something happend and I received an overwritten huge page\n");
            spin_unlock_irqrestore(&rx_subsys, flags);
            return;
        }
        polling_counter = 0;
        goto init;
    }
}

irqreturn_t card_interrupt_handler(int irq, void *dev_id)
{
    struct pci_dev *pdev = dev_id;
    struct my_driver_host_data *my_drv_data = (struct my_driver_host_data *)pci_get_drvdata(pdev);
    int ret;

    #ifdef MY_DEBUG
    printk(KERN_INFO "Myd: Interruption received\n");
    #endif

    ret = queue_work(my_drv_data->rx_wq, (struct work_struct *)&my_drv_data->rx_work);

    if (!ret)
        printk(KERN_INFO "busy\n");
    else
    {
        *(((u32 *)my_drv_data->bar2) + 9) = 0xcacabeef;
        printk(KERN_INFO "Myd: Disable interrupt\n");
    }

    return IRQ_HANDLED;
}

static int my_net_device_open(struct net_device *my_net_device) {
    printk(KERN_INFO "Myd: my_net_device_open\n");
    return 0;
}

static int my_net_device_close(struct net_device *my_net_device) {
    printk(KERN_INFO "Myd: my_net_device_close\n");
    return 0;
}

static const struct net_device_ops my_net_device_ops = {
    .ndo_open           = my_net_device_open,
    .ndo_stop           = my_net_device_close//,
    //.ndo_start_xmit     = my_net_device_xmit
};

static inline int my_linux_network_interface(struct my_driver_host_data *my_drv_data)
{
    int ret;
    u64 my_mac_invented_addr = 0x65d10d530f00;

    my_drv_data->my_net_device = alloc_etherdev(sizeof(int));
    if (my_drv_data->my_net_device == NULL)
    {
        printk(KERN_ERR "Myd: failed alloc_netdev\n");
        return -1;
    }

    printk(KERN_INFO "Myd: alloc_netdev\n");
    my_drv_data->my_net_device->netdev_ops = &my_net_device_ops;
    memcpy(my_drv_data->my_net_device->dev_addr, &my_mac_invented_addr, ETH_ALEN);

    ret = register_netdev(my_drv_data->my_net_device);
    if (ret)
    {
        printk(KERN_ERR "Myd: failed register_netdev\n");
        return ret;
    }

    return 0;
}

static int my_pcie_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    int ret = -ENODEV;
    struct my_driver_host_data *my_drv_data;

    #ifdef MY_DEBUG
    printk(KERN_INFO "Myd: pcie card with VENDOR_ID:SYSTEM_ID matched with this module advertised systems support\n");
    #endif
    
    my_drv_data = kzalloc(sizeof(struct my_driver_host_data), GFP_KERNEL);          //use vmalloc?
    if (my_drv_data == NULL)
    {
        printk(KERN_ERR "Myd: failed to alloc system mem\n");
        return ret;
    }

    my_drv_data->pdev = pdev;
    
    my_drv_data->rx_wq = alloc_workqueue("rx_wq", WQ_HIGHPRI, 0);
    if (!my_drv_data->rx_wq)
    {
        printk(KERN_ERR "Myd: alloc work queue\n");
        goto err_01;
    }
    INIT_WORK((struct work_struct *)&my_drv_data->rx_work, rx_wq_function);
    my_drv_data->rx_work.my_drv_data_ptr = my_drv_data;

    ret = pci_enable_device(pdev);
    if (ret)
    {
        printk(KERN_ERR "Myd: pci_enable_device\n");
        goto err_02;
    }

    ret = pci_set_dma_mask(pdev, DMA_BIT_MASK(64));
    if (ret)
    {
        printk(KERN_ERR "Myd: pci_set_dma_mask\n");
        goto err_03;
    }
    ret = pci_set_consistent_dma_mask(pdev, DMA_BIT_MASK(64));
    if (ret)
    {
        printk(KERN_ERR "Myd: pci_set_consistent_dma_mask\n");
        goto err_03;
    }

    pci_set_drvdata(pdev, my_drv_data);

    ret = pci_request_regions(pdev, DRV_NAME);
    if (ret)
    {
        printk(KERN_ERR "Myd: pci_request_regions\n");
        goto err_04;
    }

    my_drv_data->bar2 = pci_iomap(pdev, PCI_BAR2, pci_resource_len(pdev, PCI_BAR2));            // BAR2 used to communicate rx and tx meta information
    if (my_drv_data->bar2 == NULL)
    {
        printk(KERN_ERR "Myd: pci_iomap bar2\n");
        goto err_05;
    }

    my_drv_data->bar0 = pci_iomap(pdev, PCI_BAR0, pci_resource_len(pdev, PCI_BAR0));            // BAR0 used for register interface
    if (my_drv_data->bar0 == NULL)
    {
        printk(KERN_ERR "Myd: pci_iomap bar0\n");
        goto err_06;
    }

    pci_set_master(pdev);

    ret = pci_enable_msi(pdev);
    if (ret)
    {
        printk(KERN_ERR "Myd: pci_enable_msi\n");
        goto err_07;
    }

    // AEL2005 MDIO configuration
    ret = request_irq(pdev->irq, mdio_access_interrupt_handler, 0, DRV_NAME, pdev);
    if (ret)
    {
        printk(KERN_ERR "Myd: request_irq\n");
        goto err_08;
    }
    
    ret = configure_ael2005_phy_chips(my_drv_data);
    if (ret)
    {
        printk(KERN_ERR "Myd: warning, AEL2005 not configured\n");
    }
 
    free_irq(pdev->irq, pdev);
    // AEL2005 MDIO configuration ready

    ret = request_irq(pdev->irq, card_interrupt_handler, 0, DRV_NAME, pdev);
    if (ret)
    {
        printk(KERN_ERR "Myd: request_irq\n");
        goto err_08;
    }

    // Reserve Huge Pages
    my_drv_data->huge_page_kern_address1 = pci_alloc_consistent(pdev, 2*1024*1024, &my_drv_data->huge_page1_dma_addr);
    if (my_drv_data->huge_page_kern_address1 == NULL)
    {
        printk(KERN_ERR "Myd: alloc huge page\n");
        goto err_09;
    }
    my_drv_data->huge_page_kern_address2 = pci_alloc_consistent(pdev, 2*1024*1024, &my_drv_data->huge_page2_dma_addr);
    if (my_drv_data->huge_page_kern_address2 == NULL)
    {
        printk(KERN_ERR "Myd: alloc huge page\n");
        goto err_10;
    }

    memset(my_drv_data->huge_page_kern_address1, 0, 2*1024*1024);
    memset(my_drv_data->huge_page_kern_address2, 0, 2*1024*1024);

    // Instantiate an ethX interface in linux
    ret = my_linux_network_interface(my_drv_data);
    if (ret)
    {
        printk(KERN_ERR "Myd: my_linux_network_interface\n");
        goto err_11;
    }

    my_drv_data->current_pkt_dw_index = 32;

    // Send huge pages' address for Rx
    *(((u64 *)my_drv_data->bar2) + 8) = my_drv_data->huge_page1_dma_addr;
    *(((u64 *)my_drv_data->bar2) + 9) = my_drv_data->huge_page2_dma_addr;

    // Send huge pages' card-lock-up
    *(((u32 *)my_drv_data->bar2) + 24) = 0xcacabeef;
    *(((u32 *)my_drv_data->bar2) + 25) = 0xcacabeef;

    #ifdef MY_DEBUG
    printk(KERN_INFO "Myd: my_pcie_probe finished\n");
    #endif
    return ret;

err_11:
    pci_free_consistent(pdev, 2*1024*1024, my_drv_data->huge_page_kern_address2, my_drv_data->huge_page2_dma_addr);
err_10:
    pci_free_consistent(pdev, 2*1024*1024, my_drv_data->huge_page_kern_address1, my_drv_data->huge_page1_dma_addr);
err_09:
    free_irq(pdev->irq, pdev);
err_08:
    pci_disable_msi(pdev);
err_07:
    pci_clear_master(pdev);
    pci_iounmap(pdev, my_drv_data->bar0);
err_06:
    pci_iounmap(pdev, my_drv_data->bar2);
err_05:
    pci_release_regions(pdev);
err_04:
    pci_set_drvdata(pdev, NULL);
err_03:
    pci_disable_device(pdev);
err_02:
    destroy_workqueue(my_drv_data->rx_wq);
err_01:
    kfree(my_drv_data);
    return ret;
}

static void my_pcie_remove(struct pci_dev *pdev)
{
    struct my_driver_host_data *my_drv_data;
    
    printk(KERN_INFO "Myd: entering my_pcie_remove\n");
    my_drv_data = (struct my_driver_host_data *)pci_get_drvdata(pdev);
    if (my_drv_data)
    {
        free_irq(pdev->irq, pdev);
        flush_workqueue(my_drv_data->rx_wq);
        destroy_workqueue(my_drv_data->rx_wq);
        
        pci_free_consistent(pdev, 2*1024*1024, my_drv_data->huge_page_kern_address2, my_drv_data->huge_page2_dma_addr);
        pci_free_consistent(pdev, 2*1024*1024, my_drv_data->huge_page_kern_address1, my_drv_data->huge_page1_dma_addr);

        unregister_netdev(my_drv_data->my_net_device);
        free_netdev(my_drv_data->my_net_device);

        pci_disable_msi(pdev);
        pci_clear_master(pdev);
        pci_iounmap(pdev, my_drv_data->bar0);
        pci_iounmap(pdev, my_drv_data->bar2);
        pci_release_regions(pdev);
        pci_set_drvdata(pdev, NULL);
        pci_disable_device(pdev);

        kfree(my_drv_data);
        #ifdef MY_DEBUG
        printk(KERN_INFO "Myd: my_pcie_remove realeased resources\n");
        #endif
    }
}

pci_ers_result_t my_pcie_error(struct pci_dev *dev, enum pci_channel_state state)
{
    printk(KERN_ALERT "Myd: PCIe error: %d\n", state);
    return PCI_ERS_RESULT_RECOVERED;
}

static struct pci_error_handlers pcie_err_handlers = {
    .error_detected = my_pcie_error
};

static struct pci_driver pci_driver = {
    .name = DRV_NAME,
    .id_table = pci_id,
    .probe = my_pcie_probe,
    .remove = my_pcie_remove,
    .err_handler = &pcie_err_handlers//,
    //.suspend = my_suspend,
    //.resume = my_resume
};

module_pci_driver(pci_driver);
