/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        simple_rtt_test.c
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Simple test for rtt. TCP like
*        RTT = 0.875 * RTT + 0.125 * sampleRTT
*        sampleRTT = tstamp_b - tstamp_a
*        Network should be fixed after init
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
#include <linux/jiffies.h>      /* Needed for jiffies */
#include "my_driver.h"

irqreturn_t simple_rtt_test_interrupt_handler(int irq, void *dev_id) {
    struct pci_dev *pdev = dev_id;
    struct my_driver_host_data *my_drv_data = (struct my_driver_host_data *)pci_get_drvdata(pdev);

    my_drv_data->tstamp_b = (long)jiffies;
    atomic_set(&my_drv_data->rtt_access_rdy, 1);

    return IRQ_HANDLED;
}

int simple_rtt_test(struct my_driver_host_data *my_drv_data) {
    int ret;
    int i;
    int timeout;
    u64 tstamp_a;
    u64 sample;

    printk(KERN_INFO "Myd: Test rtt...\n");

    atomic_set(&my_drv_data->rtt_access_rdy, 0);
    tstamp_a = (long)jiffies;
    wmb();
    *(((u32 *)my_drv_data->bar2) + 11) = 0xcacabeef;
    wmb();
    
    timeout =0;
    do {
        timeout++;
        if (timeout > 1000)
            ret = 0;
    } while (!atomic_read(&my_drv_data->mdio_access_rdy));

    my_drv_data->rtt = my_drv_data->tstamp_b - tstamp_a;
    printk(KERN_INFO "Myd: first rtt: %d\n", my_drv_data->rtt);

    for (i = 0; i < 100; i++)
    {
        atomic_set(&my_drv_data->rtt_access_rdy, 0);
        tstamp_a = (long)jiffies;
        wmb();
        *(((u32 *)my_drv_data->bar2) + 11) = 0xcacabeef;
        wmb();

        timeout =0;
        do {
            timeout++;
            if (timeout > 1000)
                ret = 0;
        } while (!atomic_read(&my_drv_data->mdio_access_rdy));

        sample = my_drv_data->tstamp_b - tstamp_a;
        my_drv_data->rtt = 0.875 * my_drv_data->rtt + 0.125 * sample;
    }

    printk(KERN_INFO "Myd: rtt: %d\n", my_drv_data->rtt);

    return 0;
}
