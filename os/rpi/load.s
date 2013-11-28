#include "mem.h"
#include "armv6.h"

TEXT _start(SB), 1, $-4
	MOVW    $setR12(SB), R12	/* static base (SB) */
	SUB		$KZERO, R12
	ADD		$PHYSDRAM, R12
	MOVW	$0, R0

	MOVW    $(PsrDirq|PsrDfiq|PsrMsvc), R1  /* SVC mode: interrupts disabled */
	MOVW    R1, CPSR

	/* disable the mmu and L1 caches, invalidate caches and tlb */
	MRC		CpSC, 0, R1, C(CpCONTROL), C(0), CpMainctl
	BIC		$(CpCdcache|CpCicache|CpCpredict|CpCmmu), R1
	MCR		CpSC, 0, R1, C(CpCONTROL), C(0), CpMainctl
	MCR		CpSC, 0, R0, C(CpCACHE), C(CpCACHEinvu), CpCACHEall
	MCR		CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinv
	ISB

	/* clear mach and page tables */
	MOVW	$MACHADDR, R1
	MOVW	$KTZERO, R2
_ramZ:
	MOVW	R0, (R1)
	ADD		$4, R1
	CMP		R1, R2
	BNE		_ramZ

	MOVW    $(MACHADDR+BY2PG-4),SP /*! stack; 4 bytes for link */
	BL		,mmuinit(SB)

	/* set up domain access control and page table base */
	MOVW	$Client, R1
	MCR		CpSC, 0, R1, C(CpDAC), C(0)
	MOVW	$L1, R1
	MCR		CpSC, 0, R1, C(CpTTB), C(0)

	/* enable caches, mmu, and high vectors */
	MOVW    $1, R1
	MCR     CpSC, 0, R1, C(CpSPM), C(CpSPMperf), CpSPMctl /* counter */
	MRC     CpSC, 0, R0, C(CpCONTROL), C(0), CpMainctl
	ORR     $(CpChv|CpCdcache|CpCicache|CpCmmu), R0
	MCR     CpSC, 0, R0, C(CpCONTROL), C(0), CpMainctl
	ISB

	BL      ,main(SB)
dead:
	B       dead
	B       ,0(PC)
	BL      _div(SB)    /* hack to load _div, etc. */
