#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

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

