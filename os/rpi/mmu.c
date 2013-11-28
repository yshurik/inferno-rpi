#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

#include "armv6.h"

#define L1X(va)		FEXT((va), 20, 12)
#define L2X(va)		FEXT((va), 12, 8)

enum {
	L1lo		= KZERO/MiB,		/* L1X(UZERO)? */
	L1hi		= (256*MiB+MiB-1)/MiB,	/* L1X(USTKTOP+MiB-1)? */
};

void
mmuinit(void)
{
	PTE *l1, *l2;
	uintptr pa, va;

	l1 = (PTE*)PADDR(L1);
	l2 = (PTE*)PADDR(L2);

	/* map all of ram at KZERO */
	va = KZERO;
	for(pa = PHYSDRAM; pa < PHYSDRAM+DRAMSIZE; pa += MiB){
		l1[L1X(va)] = pa|Dom0|L1AP(Krw)|Section|Cached|Buffered;
		va += MiB;
	}

	/* identity map first MB of ram so mmu can be enabled */
	l1[L1X(PHYSDRAM)] = PHYSDRAM|Dom0|L1AP(Krw)|Section|Cached|Buffered;

	/* map i/o registers */
	va = VIRTIO;
	for(pa = PHYSIO; pa < PHYSIO+IOSIZE; pa += MiB){
		l1[L1X(va)] = pa|Dom0|L1AP(Krw)|Section;
		va += MiB;
	}

	/* double map exception vectors at top of virtual memory */
	va = HVECTORS;
	l1[L1X(va)] = (uintptr)l2|Dom0|Coarse;
	l2[L2X(va)] = PHYSDRAM|L2AP(Krw)|Small;
}

void
mmuinit1(void)
{
	PTE *l1;

	l1 = (PTE*)L1;
	m->mmul1 = l1;
}

uintptr
mmukmap(uintptr va, uintptr pa, uint size)
{
	int o;
	uint n;
	PTE *pte, *pte0;

	assert((va & (MiB-1)) == 0);
	o = pa & (MiB-1);
	pa -= o;
	size += o;
	pte = pte0 = &m->mmul1[L1X(va)];
	for(n = 0; n < size; n += MiB)
		if(*pte++ != Fault)
			return 0;
	pte = pte0;
	for(n = 0; n < size; n += MiB){
		*pte++ = (pa+n)|Dom0|L1AP(Krw)|Section;
		mmuinvalidateaddr(va+n);
	}
	cachedwbse(pte0, pte - pte0);
	return va + o;
}

