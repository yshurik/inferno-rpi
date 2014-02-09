#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

#include "../port/netif.h"
#include "etherif.h"

static void
linkproc(void)
{
	spllo();
	if (waserror())
		print("error() underflow: %r\n");
	else (*up->kpfun)(up->arg);
	pexit("end proc", 1);
}

void
kprocchild(Proc *p, void (*func)(void*), void *arg)
{
	p->sched.pc = (ulong)linkproc;
	p->sched.sp = (ulong)p->kstack+KSTACK-8;
	p->kpfun = func;
	p->arg = arg;
}

void		
validaddr(void*, ulong, int) {}

int
archether(unsigned ctlrno, Ether *ether)
{
    switch(ctlrno) {
    case 0:
        ether->type = "usb";
        ether->ctlrno = ctlrno;
        ether->irq = -1;
        ether->nopt = 0;
        ether->mbps = 100;
        return 1;
    }
    return -1;
}

/*
 * stub for ../omap/devether.c
 */
int
isaconfig(char *class, int ctlrno, ISAConf *isa)
{
    USED(ctlrno);
    USED(isa);
    return strcmp(class, "ether") == 0;
}
