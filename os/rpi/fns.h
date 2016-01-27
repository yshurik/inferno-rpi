
#define KADDR(p)	((void *)p)
#define PADDR(p)	((ulong)p)
#define DMAADDR(va)	(BUSDRAM |((uintptr)(va)))
#define DMAIO(va)	(BUSIO | ((uintptr)(va)))
#define MASK(v)   ((1UL << (v)) - 1)      /* mask `v' bits wide */
#define waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
#define procsave(p)	/* Save the mach part of the current */
			/* process state, no need for one cpu */
#define kmapinval()
#define HOWMANY(x, y)	(((x)+((y)-1))/(y))

void	(*serwrite)(char*, int);
void    (*screenputs)(char*, int);

#include "../port/portfns.h"

void	pl011_putc(int);
void	pl011_puts(char *);
void	pl011_addr(void *a, int nl);

ulong	getsp(void);
ulong   getsc(void);
ulong	getpc(void);
ulong	getcpsr(void);
ulong	getspsr(void);
ulong	getcpuid(void);
ulong	getcallerpc(void*);
u32int	lcycles(void);
int	splfhi(void);
int	tas(void *);

void	delay(int);
int	islo(void);
void	microdelay(int);
void	idlehands(void);
void	_idlehands(void);

void	coherence(void);
void	clockinit(void);
void	trapinit(void);
char *	trapname(int psr);
int	isvalid_va(void *v);
int	isvalid_wa(void *v);
void	setr13(int, void*);
void	vectors(void);
void	vtable(void);
void	setpanic(void);
void	dumpregs(Ureg*);
void	dumparound(uint addr);
int	(*breakhandler)(Ureg*, Proc*);
void	irqenable(int, void (*)(Ureg*, void*), void*);
#define intrenable(i, f, a, b, n) irqenable((i), (f), (a))

void	cachedwbinv(void);
void	cachedwbse(void*, int);
void	cachedwbinvse(void*, int);
void	cachedinvse(void*, int);
void	cacheiinvse(void*, int);
void	cacheiinv(void);
void	cacheuwbinv(void);

void	mmuinit1(void);
void	mmuinvalidateaddr(u32int);
void	screeninit(void);
void*   fbinit(int, int*, int*, int*);
int	fbblank(int blank);
void	setpower(int, int);
void	clockcheck(void);
void	armtimerset(int);
void	links(void);
int	fpiarm(Ureg*);

char*	getconf(char*);
char *	getethermac(void);
void	getramsize(Conf *);

void	drawqlock(void);
void	drawqunlock(void);
int	candrawqlock(void);
void	swcursorinit(void);

int	isaconfig(char *, int, ISAConf *);

uintptr dmaaddr(void *va);
void 	dmastart(int, int, int, void*, void*, int);
int 	dmawait(int);

#define PTR2UINT(p)     ((uintptr)(p))
#define UINT2PTR(i)     ((void*)(i))

