#!/bin/bash
coregen -p mac/ -b mac/xgmac_mdio.xco
git checkout -- mac/xgmac_mdio.xco
coregen -p mac/ -b mac/xgmac.xco
git checkout -- mac/xgmac.xco
coregen -p pcie/ -b pcie/endpoint_blk_plus_v1_15.xco
git checkout -- pcie/endpoint_blk_plus_v1_15.xco
coregen -p xaui/ -b xaui/xaui.xco
git checkout -- xaui/xaui.xco
#coregen -p xaui_dcm/ -b xaui_dcm/xaui_dcm.xaw
#git checkout -- xaui_dcm/xaui_dcm.xaw
