
implement Init;

include "sys.m";
	sys:    Sys;

Bootpreadlen: con 128;

Init: module
{
	init:   fn();
};

init()
{
	sys = load Sys Sys->PATH;
	sys->print("Hey, this is Hello World from Dis!\n\n");
}
