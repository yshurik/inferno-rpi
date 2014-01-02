
#define HZ      	(100)       /*! clock frequency */
#define MS2HZ       (1000/HZ)   /*! millisec per clock tick */
#define TK2SEC(t)   ((t)/HZ)    /*! ticks to seconds */
#define MS2TK(t)    ((t)/MS2HZ) /*! milliseconds to ticks */
enum { Mhz = 1000 * 1000 };

#define MACHP(n)    (n == 0 ? (Mach*)(MACHADDR) : (Mach*)0)

typedef struct ISAConf ISAConf;
typedef struct Lock Lock;
typedef struct Ureg Ureg;
typedef struct Label Label;
typedef struct FPenv FPenv;
typedef struct Mach Mach;
typedef struct MMMU	MMMU;
typedef struct FPU FPU;
typedef ulong  Instr;
typedef struct Conf Conf;
typedef u32int PTE;

struct Lock
{
	ulong   key;
	ulong   sr;
	ulong   pc;
	int pri;
};

struct Label
{
	ulong   sp;
	ulong   pc;
};

enum
{
	FPINIT,
	FPACTIVE,
	FPINACTIVE,
	FPEMU,

	/* bits or'd with the state */
	FPILLEGAL= 0x100,
};

struct FPenv
{
	ulong	status;
	ulong   control;
	ushort  fpistate;   /* emulated fp */
	ulong   regs[8][3]; /* emulated fp */
};

struct FPU
{
	FPenv env;
};

struct Conf
{
	ulong   nmach;      /* processors */
	ulong   nproc;      /* processes */
	ulong   npage;      /* total physical pages of memory */
	ulong   npage0;     /* total physical pages of memory */
	ulong   npage1;     /* total physical pages of memory */
	ulong   base0;      /* base of bank 0 */
	ulong   base1;      /* base of bank 1 */
	ulong   ialloc;     /* max interrupt time allocation in bytes */
	ulong   topofmem;   /* top addr of memory */
	int     monitor;    /* flag */
};

/*
 *  MMU stuff in Mach.
 */
struct MMMU
{
	PTE*	mmul1;		/* l1 for this processor */
};

#include "../port/portdat.h"

struct Mach
{
	ulong   splpc;		/* pc of last caller to splhi */
	int     machno;		/* physical id of processor */
	Proc*   proc;		/* current process on this processor */
	ulong   ticks;		/* of the clock since boot time */
	Label   sched;		/* scheduler wakeup */
	int	intr;
	uvlong	fastclock;	/* last sampled value */
	ulong	cpuhz;
	MMMU;

	/* stacks for exceptions */
	ulong   fiqstack[5];
	ulong   irqstack[5];
	ulong   abtstack[5];
	ulong   undstack[5];
	ulong	sysstack[5];
	int	stack[1];
};

extern Mach *m;
extern Proc *up;

struct
{
	Lock;
	int machs;          /* bitmap of active CPUs */
	int exiting;        /* shutdown */
} active;

#define NISAOPT     8

struct ISAConf {
	char    *type;
	ulong   port;
	int irq;
	ulong   dma;
	ulong   mem;
	ulong   size;
	ulong   freq;

	int nopt;
	char    *opt[NISAOPT];
};

/*
 *  hardware info about a device
 */
typedef struct {
	ulong	port;
	int	size;
} Devport;


struct DevConf
{
	ulong	intnum;			/* interrupt number */
	char	*type;			/* card type, malloced */
	int	nports;			/* Number of ports */
	Devport	*ports;			/* The ports themselves */
};

