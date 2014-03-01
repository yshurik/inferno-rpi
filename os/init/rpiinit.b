
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

err(s: string) { sys->fprint(sys->fildes(2), "init: %s\n", s); }

dobind(f, t: string, flags: int) {
	if(sys->bind(f, t, flags) < 0)
		err(sys->sprint("can't bind %s on %s: %r", f, t));
}

init(nil: ref Draw->Context, nil: list of string)
{
	shell := load Sh "/dis/sh.dis";
	usbd := load Sh "/dis/usb/usbd.dis";
	sys = load Sys Sys->PATH;

	dobind("#p",  "/prog", sys->MREPL);
	dobind("#i",  "/dev", sys->MREPL);	# draw device
	dobind("#c",  "/dev", sys->MAFTER);	# console device
	dobind("#u",  "/dev", sys->MAFTER);	# usb subsystem
	dobind("#S",  "/dev", sys->MAFTER);	# sdcard subsystem
	dobind("#e",  "/env", sys->MREPL|sys->MCREATE);
	dobind("#l0", "/net", Sys->MREPL);
	dobind("#I",  "/net", sys->MAFTER);	# IP

	#sdd := sys->open("/dev/sdM0/data", Sys->OREAD);
	#sdc := sys->open("/dev/sdM0/ctl", Sys->OWRITE);
	#buf := array[512] of byte;
	#n := sys->read(sdd, buf, len buf);
	#sys->write(sdc, buf, n);
	#sys->print("fdisk:\n%s\n",string buf);
	#sdd = sdc = nil;

	x := 10.25;
	y := 734.;
	sys->print("\n\nfloat point div %f/%f=%f\n\n", x,y,x/y);

	usbd->init(nil,nil);
	spawn shell->init(nil, nil);
}

