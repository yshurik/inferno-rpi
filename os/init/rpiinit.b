
implement Init;

include "sys.m";
	sys:    Sys;
include "draw.m";

Sh: module
{
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

Init: module
{
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	shell := load Sh "/dis/sh.dis";
	sys = load Sys Sys->PATH;
	sys->print("init: starting shell\n");

	sys->bind("#p", "/prog", sys->MREPL);
	sys->bind("#i", "/dev", sys->MREPL);    # draw device
	sys->bind("#c", "/dev", sys->MAFTER);   # console device
	sys->bind("#u", "/dev", sys->MAFTER);   # usb subsystem

	spawn shell->init(nil, nil);
}

