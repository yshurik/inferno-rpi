
#include "mem.h"
#include "armv6.h"

TEXT setlabel(SB), $-4
	MOVW    R13, 0(R0)
	MOVW    R14, 4(R0)
	MOVW    $0, R0
	RET

TEXT gotolabel(SB), $-4
	MOVW    0(R0), R13
	MOVW    4(R0), R14
	MOVW    $1, R0
	RET

TEXT getcallerpc(SB), $-4
	MOVW    0(SP), R0
	RET

TEXT getsp(SB), $-4
	MOVW    SP, R0
	RET

TEXT getpc(SB), $-4
	MOVW    R14, R0
	RET

TEXT getsc(SB), $-4
	MRC     CpSC, 0, R0, C(CpCONTROL), C(0), CpMainctl
	RET

TEXT getcpsr(SB), $-4
	MOVW	CPSR, R0
	RET

TEXT getspsr(SB), $-4
	MOVW	SPSR, R0
	RET

TEXT coherence(SB), $-4
	BARRIERS
	RET

TEXT splhi(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)   /* m->splpc */
	MOVW	CPSR, R0
	ORR		$(PsrDirq), R0, R1
	MOVW	R1, CPSR
	RET

TEXT spllo(SB), $-4
	MOVW	CPSR, R0
	BIC		$(PsrDirq|PsrDfiq), R0, R1
	MOVW	R1, CPSR
	RET

TEXT splx(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)   /* m->splpc */
TEXT splxpc(SB), $-4
	MOVW	R0, R1
	MOVW	CPSR, R0
	MOVW	R1, CPSR
	RET

TEXT splfhi(SB), 1, $-4
	MOVW	$(MACHADDR), R2		/* save caller pc in Mach */
	MOVW	R14, 0(R2)
	MOVW	CPSR, R0			/* turn off irqs and fiqs */
	ORR	$(PsrDirq|PsrDfiq), R0, R1
	MOVW	R1, CPSR
	RET

TEXT islo(SB), $-4
	MOVW	CPSR, R0
	AND		$(PsrDirq), R0
	EOR		$(PsrDirq), R0
	RET

TEXT tas(SB), $-4
TEXT _tas(SB), $-4
	MOVW    R0, R1
	MOVW    $0xDEADDEAD, R2
	SWPW    R2, (R1), R0
	RET

TEXT getcpuid(SB), $-4
	MRC		CpSC, 0, R0, C(CpID), C(0)
	RET

TEXT lcycles(SB), $-4
	MRC CpSC, 0, R0, C(CpSPM), C(CpSPMperf), CpSPMcyc
	RET

/*
 * drain write buffer
 * writeback and invalidate data cache
 */
TEXT cachedwbinv(SB), 1, $-4
	DSB
	MOVW	$0, R0
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEwbi), CpCACHEall
	RET

/*
 * cachedwbinvse(va, n)
 *   drain write buffer
 *   writeback and invalidate data cache range [va, va+n)
 */
TEXT cachedwbinvse(SB), 1, $-4
	MOVW	R0, R1		/* DSB clears R0 */
	DSB
	MOVW	n+4(FP), R2
	ADD	R1, R2
	SUB	$1, R2
	BIC	$(CACHELINESZ-1), R1
	BIC	$(CACHELINESZ-1), R2
	MCRR(CpSC, 0, 2, 1, CpCACHERANGEdwbi)
	RET

/*
 * cacheiinvse(va, n)
 *   invalidate instructions cache range [va, va+n)
 */
TEXT cacheiinvse(SB), 1, $-4
	MOVW	R0, R1		/* DSB clears R0 */
	DSB
	MOVW	n+4(FP), R2
	ADD	R1, R2
	SUB	$1, R2
	BIC	$(CACHELINESZ-1), R1
	BIC	$(CACHELINESZ-1), R2
	MCRR(CpSC, 0, 2, 1, CpCACHERANGEinvi)
	RET

/*
 * cachedwbse(va, n)
 *   drain write buffer
 *   writeback data cache range [va, va+n)
 */
TEXT cachedwbse(SB), 1, $-4
	MOVW	R0, R1		/* DSB clears R0 */
	DSB
	MOVW	n+4(FP), R2
	ADD	R1, R2
	BIC	$(CACHELINESZ-1), R1
	BIC	$(CACHELINESZ-1), R2
	MCRR(CpSC, 0, 2, 1, CpCACHERANGEdwb)
	RET

/*
 * cachedinvse(va, n)
 *   drain write buffer
 *   invalidate data cache range [va, va+n)
 */
TEXT cachedinvse(SB), 1, $-4
        MOVW    R0, R1          /* DSB clears R0 */
        DSB
        MOVW    n+4(FP), R2
        ADD     R1, R2
        SUB     $1, R2
        BIC     $(CACHELINESZ-1), R1
        BIC     $(CACHELINESZ-1), R2
        MCRR(CpSC, 0, 2, 1, CpCACHERANGEinvd)
        RET

/*
 * drain write buffer and prefetch buffer
 * writeback and invalidate data cache
 * invalidate instruction cache
 */
TEXT cacheuwbinv(SB), 1, $-4
	BARRIERS
	MOVW	$0, R0
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEwbi), CpCACHEall
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEinvi), CpCACHEall
	RET

/*
 * invalidate instruction cache
 */
TEXT cacheiinv(SB), 1, $-4
	MOVW	$0, R0
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEinvi), CpCACHEall
	RET

/*
 * invalidate tlb
 */
TEXT mmuinvalidate(SB), 1, $-4
	MOVW	$0, R0
	MCR	CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinv
	BARRIERS
	RET

/*
 * mmuinvalidateaddr(va)
 *   invalidate tlb entry for virtual page address va, ASID 0
 */
TEXT mmuinvalidateaddr(SB), 1, $-4
	MCR	CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinvse
	BARRIERS
	RET

TEXT _idlehands(SB), $-4
	BARRIERS
	MOVW	CPSR, R3
	BIC	$(PsrDirq|PsrDfiq), R3, R1		/* spllo */
	MOVW	R1, CPSR

	MOVW	$0, R0				/* wait for interrupt */
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEintr), CpCACHEwait
	ISB

	MOVW	R3, CPSR			/* splx */
	RET

