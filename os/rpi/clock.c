
#include "../port/portclock.c"

#define SYSTIMERS   (IOBASE+0x3000)
#define ARMTIMER    (IOBASE+0xB400)

enum {
	SystimerFreq    = 1*Mhz,
	MaxPeriod   = SystimerFreq/HZ,
	MinPeriod   = SystimerFreq/(100*HZ)
};

typedef struct Systimers Systimers;
typedef struct Armtimer Armtimer;

struct Systimers {
	u32int  cs;
	u32int  clo;
	u32int  chi;
	u32int  c0;
	u32int  c1;
	u32int  c2;
	u32int  c3;
};

struct Armtimer {
	u32int  load;
	u32int  val;
	u32int  ctl;
	u32int  irqack;
	u32int  irq;
	u32int  maskedirq;
	u32int  reload;
	u32int  predivider;
	u32int  count;
};

enum {
	CntPrescaleShift    = 16,       /* freq is sys_clk/(prescale+1) */
	CntPrescaleMask     = 0xFF,
	CntEnable           = 1<<9,
	TmrDbgHalt          = 1<<8,
	TmrEnable           = 1<<7,
	TmrIntEnable        = 1<<5,
	TmrPrescale1        = 0x00<<2,
	TmrPrescale16       = 0x01<<2,
	TmrPrescale256      = 0x02<<2,
	CntWidth16          = 0<<1,
	CntWidth32          = 1<<1
};

static void
clockintr(Ureg * ureg, void *)
{
	Systimers *tn;

	tn = (Systimers*)SYSTIMERS;
	/* dismiss interrupt */
	tn->cs = 1<<3;
	timerintr(ureg, 0);
}

void
clockinit(void)
{
	Systimers *tn;
	Armtimer *tm;
	u32int t0, t1;
	u32int tstart, tend;

	tn = (Systimers*)SYSTIMERS;
	tm = (Armtimer*)ARMTIMER;
	tm->load = 0;
	tm->ctl = TmrPrescale1|CntEnable|CntWidth32;

	tstart = tn->clo;
	do{
		t0 = lcycles();
	}while(tn->clo == tstart);
	tend = tstart + 10000; /* 10 msecs */
	do{
		t1 = lcycles();
	}while(tn->clo != tend);
	t1 -= t0;
	m->cpuhz = 100 * t1;

	tn->c3 = tn->clo - 1;
	irqenable(IRQtimer3, clockintr, nil);
}

void
clockcheck(void) { return; }

uvlong
fastticks(uvlong *hz)
{
	Systimers *tn;
	ulong lo, hi;

	tn = (Systimers*)SYSTIMERS;
	if(hz)
		*hz = SystimerFreq;
	do{
		hi = tn->chi;
		lo = tn->clo;
	}while(tn->chi != hi);
	m->fastclock = (uvlong)hi<<32 | lo;
	return m->fastclock;
}

void
timerset(uvlong next)
{
	Systimers *tn;
	vlong now, period;

	tn = (Systimers*)SYSTIMERS;
	now = fastticks(nil);
	period = next - fastticks(nil);
	if(period < MinPeriod)
		next = now + MinPeriod;
	else if(period > MaxPeriod)
		next = now + MaxPeriod;
	tn->c3 = (ulong)next;
}
