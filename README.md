This is compilation of Labs completed by LynxLine (http://lynxline.com/projects/labs-portintg-inferno-os-to-raspberry-pi/) into the source code repository.

We started a small and exciting project just for fun as “Porting Inferno OS to Raspberry Pi”. Of course we would like to run it there as native, not hosted. It was always declared that this OS is very simple for porting to new platforms, so let’s just research this and reach new distilled experiences of system programming. Also this OS is very small, simple and easy to tweak for research purposes.

We decided to organize it as some set of small labs with very detailed steps of what is done to reach results and make everything easy to reproduce.

Season 1: Road to boot…

1.	[Lab 1, Compiler](http://lynxline.com/lab-1-compiler/)
2.	[Lab 2, Hardware](http://lynxline.com/lab-2-hardware/)
3.	[Lab 3, R-Pi Booting process](http://lynxline.com/lab-3-r-pi-booting-process/)
4.	[Lab 4, Loading kernel](http://lynxline.com/lab-4-loading-kernel/)
5.	[Lab 5, Hello World](http://lynxline.com/lab-5-hello-world/)
6.	[Lab 6, Compile something](http://lynxline.com/lab-6-compile-something/)
7.	[Lab 7, linking, planning next](http://lynxline.com/lab-7-linking-more-initialization/)
8.	[Lab 8, memory model](http://lynxline.com/lab-8-memory-model/)
9.	[Lab 9, coding assembler part](http://lynxline.com/lab-9-coding-assembler-part/)
10.	[Lab 10, Bss, memory pools, malloc](http://lynxline.com/lab-10-bss-menpools-malloc/)
11.	[Lab 11, _div, testing print](http://lynxline.com/lab-11-_div-testing-print/)
12.	[Lab 12, interrupts, part 1](http://lynxline.com/lab-12-interrupts-part-1/)
13.	[Lab 13, interrupts, part 2](http://lynxline.com/lab-13-interrupts-part2/)
14.	[Lab 14, interrupts, part 3](http://lynxline.com/lab-14-interrupts-part-3/)
15.	[Lab 15, Eve, Hello World from Limbo!](http://lynxline.com/lab-15-eve-hello-world-from-limbo/)

Season 2: Close to hardware…

16.	[Lab 16, Adding clocks, timers, converging to 9pi codes](http://lynxline.com/lab-16/)
17.	[Lab 17, mmu init](http://lynxline.com/lab-17-mmu-init/)
18.	[Lab 18, we have a screen!](http://lynxline.com/lab-18-we-have-a-screen/)
19.	[Lab 19, keyboard through serial, fixes to get Ls](http://lynxline.com/lab-19-keyboard-through-serial-fixes-to-get-ls/)
20.	[Lab 20, devusb, usbdwc and firq, first step to usb](http://lynxline.com/lab-20-devusb-usbdwc-and-firq-first-step-to-usb/)
21.	[Lab 21, porting usbd, fixed in allocb, see usb in actions](http://lynxline.com/lab-21-porting-usbd-fixed-in-allocb-see-usb-in-actions/)
22.	[Lab 22, Usb keyboard](http://lynxline.com/lab-22-usb-keyboard/)
23.	[Lab 23, hard disk or SD card](http://lynxline.com/lab-23-hard-disk-or-sd-card/)
24.	[Lab 24, network, part 1](http://lynxline.com/lab-24-network-part-1/)
25.	[Lab 25, network, part 2](http://lynxline.com/lab-25-network-part-2/)
26.	[Lab 26, floating point](http://lynxline.com/lab-26-floating-point/)


Downloads:

* [http://tor.lynxline.com/inferno-raspberry-pi-beta1-fat.zip](http://tor.lynxline.com/inferno-raspberry-pi-beta1-fat.zip)

Installation:

1.	Download latest zip package from [Downloads](https://bitbucket.org/infpi/inferno-rpi/downloads)
2.	Pepare SD card with just one DOS partition (just format into the dos)
3.	Unzip all files to SD (boot.scr, kernel.bin, ... should in root of SD)
4.	Boot Raspberry Pi
5.	By default it starts ```styxlisten -A tcp!*!564 export /```, so you can mount it on other host by ```mount -A tcp!10.0.56.101!564 /n/remote/rpi``` (-A means no auth, IP is for example, see what it got by DHCP)


Special thanks:

* Charles Forsyth
* Richard Miller
* Peter D. Finn