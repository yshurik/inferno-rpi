#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "ureg.h"
#include "armv6.h"
#include "../port/error.h"

#define INTREGS		(VIRTIO+0xB200)

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

int isvalid_wa(void *v) { return (ulong)v < conf.topofmem && !((ulong)v & 3); }
int isvalid_va(void *v) { return (ulong)v < conf.topofmem; }

enum { Nvec = 8, Fiqenable = 1<<7 }; /* # of vectors */
typedef struct Vpage0 {
	void    (*vectors[Nvec])(void);
	u32int  vtable[Nvec];
} Vpage0;

typedef struct Intregs Intregs;
typedef struct Vctl Vctl;

/*
 * interrupt control registers
 */
struct Intregs {
        u32int  ARMpending;
        u32int  GPUpending[2];
        u32int  FIQctl;
        u32int  GPUenable[2];
        u32int  ARMenable;
        u32int  GPUdisable[2];
        u32int  ARMdisable;
};

struct Vctl {
	Vctl	*next;
	int		irq;
	u32int	*reg;
	u32int	mask;
	void	(*f)(Ureg*, void*);
	void	*a;
};
static Vctl *vctl, *vfiq;

void
intrsoff(void)
{
	Intregs *ip;
	int disable;

	ip = (Intregs*)INTREGS;
	disable = ~0;
	ip->GPUdisable[0] = disable;
	ip->GPUdisable[1] = disable;
	ip->ARMdisable = disable;
	ip->FIQctl = 0;
}

void
trapinit(void)
{
	Vpage0 *vpage0;

	intrsoff();

	/* set up the exception vectors */
	vpage0 = (Vpage0*)HVECTORS;
	memmove(vpage0->vectors, vectors, sizeof(vpage0->vectors));
	memmove(vpage0->vtable,  vtable,  sizeof(vpage0->vtable));
	cacheuwbinv();

	setr13(PsrMfiq, (u32int*)(FIQSTKTOP));
	setr13(PsrMirq, m->irqstack+nelem(m->irqstack));
	setr13(PsrMabt, m->abtstack+nelem(m->abtstack));
	setr13(PsrMund, m->undstack+nelem(m->undstack));
	setr13(PsrMsys, m->undstack+nelem(m->sysstack));
	coherence();
}

/*
 * called direct from intr.s to handle fiq interrupt.
 */
void
fiq(Ureg *ureg)
{
	Vctl *v;

	v = vfiq;
	if(v == nil)
		panic("unexpected item in bagging area");
	m->intr++;
	m->inidle = 0;
	ureg->pc -= 4;
	coherence();
	v->f(ureg, v->a);
	coherence();
}

void
irqenable(int irq, void (*f)(Ureg*, void*), void* a)
{
	Vctl *v;
	Intregs *ip;
	u32int *enable;

	ip = (Intregs*)INTREGS;
	v = (Vctl*)malloc(sizeof(Vctl));
	if(v == nil)
		panic("irqenable: no mem");
	v->irq = irq;
	if(irq >= IRQbasic){
		enable = &ip->ARMenable;
		v->reg = &ip->ARMpending;
		v->mask = 1 << (irq - IRQbasic);
	}else{
		enable = &ip->GPUenable[irq/32];
		v->reg = &ip->GPUpending[irq/32];
		v->mask = 1 << (irq % 32);
	}
	v->f = f;
	v->a = a;
	if(irq == IRQfiq){
		assert((ip->FIQctl & Fiqenable) == 0);
		assert((*enable & v->mask) == 0);
		vfiq = v;
		ip->FIQctl = Fiqenable | irq;
	}else{
		v->next = vctl;
		vctl = v;
		*enable = v->mask;
	}

	//print("Enabled irq %d\n", irq);
}

/* called by trap to handle irq interrupts. */
static void
irq(Ureg* ureg)
{
	Vctl *v;
	for(v = vctl; v; v = v->next) {
		if(*v->reg & v->mask) {
			coherence();
			v->f(ureg, v->a);
			coherence();
		}
	}
}

void
setpanic(void)
{
	spllo();
	consoleprint = 1;
}

static void
sys_trap_error(int type)
{
	char errbuf[ERRMAX];
	sprint(errbuf, "sys: trap: %s\n", trapname(type));
	error(errbuf);
}

static void
faultarm(Ureg *ureg)
{
	char buf[ERRMAX];

	sprint(buf, "sys: trap: fault pc=%8.8lux", (ulong)ureg->pc);
	if(0){
		iprint("%s\n", buf);

		print("%s\n", buf);
		print("Around PC?: %8.8uX\n", ureg->pc);
		dumparound(ureg->pc);

		dumpregs(ureg);
		for(;;);
	}
	disfault(ureg, buf);
}

Instr BREAK = 0xE6BAD010;
int (*catchdbg)(Ureg *, uint);
#define waslo(sr) (!((sr) & (PsrDirq|PsrDfiq)))

void
trap(Ureg *ureg)
{
	int rem, itype, t;

	if(up != nil)
		rem = ((char*)ureg)-up->kstack;
	else rem = ((char*)ureg)-(char*)m->stack;

	if(ureg->type != PsrMfiq && rem < 256) {
		dumpregs(ureg);
		panic("trap %d stack bytes remaining (%s), "
			  "up=#%8.8lux ureg=#%8.8lux pc=#%8.8ux"
			  ,rem, up?up->text:"", up, ureg, ureg->pc);
		for(;;);
	}

	itype = ureg->type;
	/*	All interrupts/exceptions should be resumed at ureg->pc-4,
		except for Data Abort which resumes at ureg->pc-8. */
	if(itype == PsrMabt+1)
		ureg->pc -= 8;
	else ureg->pc -= 4;

	if(up){
		up->pc = ureg->pc;
		up->dbgreg = ureg;
	}

	switch(itype) {
	case PsrMirq:
		t = m->ticks;		/* CPU time per proc */
		up = nil;		/* no process at interrupt level */
		irq(ureg);
		m->inidle = 0;
		up = m->proc;
		preemption(m->ticks - t);
		m->intr++;
		break;

	case PsrMund:
		if(*(ulong*)ureg->pc == BREAK && breakhandler) {
			int s;
			Proc *p;

			p = up;
			s = breakhandler(ureg, p);
			if(s == BrkSched) {
				p->preempted = 0;
				sched();
			} else if(s == BrkNoSched) {
				/* stop it being preempted until next instruction */
				p->preempted = 1;
				if(up)
					up->dbgreg = 0;
				return;
			}
			break;
		}
		if(up == nil) goto faultpanic;
		spllo();
		if(waserror()) {
			if(waslo(ureg->psr) && up->type == Interp)
				disfault(ureg, up->env->errstr);
			setpanic();
			dumpregs(ureg);
			panic("%s", up->env->errstr);
		}
		if(!fpiarm(ureg)) {
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		poperror();
		break;

	case PsrMsvc: /* Jump through 0 or SWI */
		if(waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		setpanic();
		dumpregs(ureg);
		panic("SVC/SWI exception");
		break;

	case PsrMabt: /* Prefetch abort */
		if(catchdbg && catchdbg(ureg, 0))
			break;
		/* FALL THROUGH */
	case PsrMabt+1: /* Data abort */
		if(waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			faultarm(ureg);
		}
		print("Data Abort\n");
		/* FALL THROUGH */

	default:
faultpanic:
		setpanic();
		dumpregs(ureg);
		panic("exception %uX %s\n", ureg->type, trapname(ureg->type));
		break;
	}

	m->inidle = 0;

	splhi();
	if(up)
		up->dbgreg = 0;		/* becomes invalid after return from trap */
}
