
implement Init;

include "sys.m";
	sys:    Sys;
include "draw.m";

Sh: module {
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

Init: module {
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

Usbd: module {
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	shell := load Sh "/dis/sh.dis";
	usbd := load Sh "/dis/usb/usbd.dis";
	sys = load Sys Sys->PATH;

	sys->bind("#p", "/prog", sys->MREPL);
	sys->bind("#i", "/dev", sys->MREPL);    # draw device
	sys->bind("#c", "/dev", sys->MAFTER);   # console device
	sys->bind("#u", "/dev", sys->MAFTER);   # usb subsystem
	sys->bind("#S", "/dev", sys->MAFTER);   # sdcard subsystem

	#sdd := sys->open("/dev/sdM0/data", Sys->OREAD);
	#sdc := sys->open("/dev/sdM0/ctl", Sys->OWRITE);
	#buf := array[512] of byte;
	#n := sys->read(sdd, buf, len buf);
	#sys->write(sdc, buf, n);
	#sys->print("fdisk:\n%s\n",string buf);
	#sdd = sdc = nil;

	usbd->init(nil,nil);
	spawn shell->init(nil, nil);
}

