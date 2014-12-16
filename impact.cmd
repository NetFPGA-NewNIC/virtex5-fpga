setMode -bs
setCable -port auto
Identify -inferir 
identifyMPM 
assignFile -p 1 -file "./bitfile/my_top.bit"
Program -p 1 
quit