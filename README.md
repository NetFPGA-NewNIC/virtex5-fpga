BAR MAPPING
============
NIC prototype for virtex5 netfpga-10g

## BAR 0

| BAR NUMBER | Offset in bytes | Used for | Access type | Access width |
|:----------:|:---------------:|:--------:|:-----------:|:------------:|
| BAR0 | 16 | MDIO configuration | WRO | DW |

## BAR 2

| BAR NUMBER | Offset in bytes | Used for | Access type | Access width |
|:----------:|:---------------:|:--------:|:-----------:|:------------:|
| BAR2 | 32 | Host going to sleep | WRO | DW |
| BAR2 | 64 | Rx huge page addr 1 | WRO | QW |
| BAR2 | 72 | Rx huge page addr 2 | WRO | QW |
| BAR2 | 96 | Rx huge page ready 1 | WRO | DW |
| BAR2 | 120 | Rx host synch | WRO | QW |
| BAR2 | 100 | Rx huge page ready 2 | WRO | DW |
| BAR2 | 128 | Tx huge page addr 1 | WRO | QW |
| BAR2 | 136 | Tx huge page addr 2 | WRO | QW |
| BAR2 | 160 | Tx huge page ready 1 | WRO | DW |
| BAR2 | 164 | Tx huge page ready 2 | WRO | DW |
| BAR2 | 176 | Tx completion buffer address | WRO | QW |
| BAR2 | 184 | Tx host synch | WRO | QW |