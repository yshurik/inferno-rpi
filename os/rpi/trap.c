#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "ureg.h"
#include "armv6.h"
#include "../port/error.h"

static char *trapnames[PsrMask+1] = {
	[ PsrMusr ] "user mode",
	[ PsrMfiq ] "fiq interrupt",
	[ PsrMirq ] "irq interrupt",
	[ PsrMsvc ] "svc/swi exception",
	[ PsrMabt ] "prefetch abort/data abort",
	[ PsrMabt+1 ] "data abort",
	[ PsrMund ] "undefined instruction",
	[ PsrMsys ] "sys trap",
};

char *
trapname(int psr)
{
	char *s;

	s = trapnames[psr & PsrMask];
	if(s == nil)
		s = "Undefined trap";
	return s;
}

int
isvalid_wa(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem && !((ulong)v & 3);
}

int
isvalid_va(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem;
}

