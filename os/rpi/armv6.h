
/*
 * Program Status Registers
 */
#define PsrMusr		0x00000010	/* mode */
#define PsrMfiq		0x00000011
#define PsrMirq		0x00000012
#define PsrMsvc		0x00000013	/* `protected mode for OS' */
#define PsrMmon		0x00000016	/* `secure monitor' (trustzone hyper) */
#define PsrMabt		0x00000017
#define PsrMund		0x0000001B
#define PsrMsys		0x0000001F	/* `privileged user mode for OS' (trustzone) */
#define PsrMask		0x0000001F

#define PsrDfiq		0x00000040	/* disable FIQ interrupts */
#define PsrDirq		0x00000080	/* disable IRQ interrupts */

#define PsrV		0x10000000	/* overflow */
#define PsrC		0x20000000	/* carry/borrow/extend */
#define PsrZ		0x40000000	/* zero */
#define PsrN		0x80000000	/* negative/less than */

/*
 * Coprocessors
 */
#define CpFP        10          /* float FP, VFP cfg. */
#define CpDFP       11          /* double FP */
#define CpSC        15          /* System Control */

/*
 * Primary (CRn) CpSC registers.
 */
#define CpID        0           /* ID and cache type */
#define CpCONTROL   1           /* miscellaneous control */
#define CpTTB       2           /* Translation Table Base(s) */
#define CpDAC       3           /* Domain Access Control */
#define CpFSR       5           /* Fault Status */
#define CpFAR       6           /* Fault Address */
#define CpCACHE     7           /* cache/write buffer control */
#define CpTLB       8           /* TLB control */
#define CpCLD       9           /* L2 Cache Lockdown, op1==1 */
#define CpTLD       10          /* TLB Lockdown, with op2 */
#define CpVECS      12          /* vector bases, op1==0, Crm==0, op2s (cortex) */
#define CpPID       13          /* Process ID */
#define CpSPM       15          /* system performance monitor (arm1176) */

/*
 * CpCACHE Secondary (CRm) registers and opcode2 fields.  op1==0.
 * In ARM-speak, 'flush' means invalidate and 'clean' means writeback.
 */
#define CpCACHEintr 0           /* interrupt (op2==4) */
#define CpCACHEisi  1           /* inner-sharable I cache (v7) */
#define CpCACHEpaddr    4           /* 0: phys. addr (cortex) */
#define CpCACHEinvi 5           /* instruction, branch table */
#define CpCACHEinvd 6           /* data or unified */
#define CpCACHEinvu 7           /* unified (not on cortex) */
#define CpCACHEva2pa    8           /* va -> pa translation (cortex) */
#define CpCACHEwb   10          /* writeback */
#define CpCACHEinvdse   11          /* data or unified by mva */
#define CpCACHEwbi  14          /* writeback+invalidate */

#define CpCACHEall  0           /* entire (not for invd nor wb(i) on cortex) */
#define CpCACHEse   1           /* single entry */
#define CpCACHEsi   2           /* set/index (set/way) */
#define CpCACHEtest 3           /* test loop */
#define CpCACHEwait 4           /* wait (prefetch flush on cortex) */
#define CpCACHEdmbarr   5           /* wb only (cortex) */
#define CpCACHEflushbtc 6           /* flush branch-target cache (cortex) */
#define CpCACHEflushbtse 7          /* ⋯ or just one entry in it (cortex) */

/*
 * CpSPM Secondary (CRm) registers and opcode2 fields.
 */
#define CpSPMctl    0           /* performance monitor control */
#define CpSPMcyc    1           /* cycle counter register */
#define CpSPMperf   12          /* various counters */

/*
 * CpCONTROL op2 codes, op1==0, Crm==0.
 */
#define CpMainctl   0
#define CpAuxctl    1
#define CpCPaccess  2

/*
 * CpCONTROL: op1==0, CRm==0, op2==CpMainctl.
 * main control register.
 * cortex/armv7 has more ops and CRm values.
 */
#define CpCmmu      0x00000001  /* M: MMU enable */
#define CpCalign    0x00000002  /* A: alignment fault enable */
#define CpCdcache   0x00000004  /* C: data cache on */
#define CpCsbo (3<<22|1<<18|1<<16|017<<3)   /* must be 1 (armv7) */
#define CpCsbz (CpCtre|1<<26|CpCve|1<<15|7<<7)  /* must be 0 (armv7) */
#define CpCsw       (1<<10)     /* SW: SWP(B) enable (deprecated in v7) */
#define CpCpredict  0x00000800  /* Z: branch prediction (armv7) */
#define CpCicache   0x00001000  /* I: instruction cache on */
#define CpChv       0x00002000  /* V: high vectors */
#define CpCrr       (1<<14) /* RR: round robin vs random cache replacement */
#define CpCha       (1<<17)     /* HA: hw access flag enable */
#define CpCdz       (1<<19)     /* DZ: divide by zero fault enable */
#define CpCfi       (1<<21)     /* FI: fast intrs */
#define CpCve       (1<<24)     /* VE: intr vectors enable */
#define CpCee       (1<<25)     /* EE: exception endianness */
#define CpCnmfi     (1<<27)     /* NMFI: non-maskable fast intrs. */
#define CpCtre      (1<<28)     /* TRE: TEX remap enable */
#define CpCafe      (1<<29)     /* AFE: access flag (ttb) enable */

//#define PADDR(va)	(PHYSDRAM | ((va) & ~KSEGM))

#define ISB \
	MOVW	$0, R0; \
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEinvi), CpCACHEwait

#define DSB \
	MOVW	$0, R0; \
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEwb), CpCACHEwait

#define BARRIERS ISB; DSB

#define LVECTORS	0x00000000
#define HVECTORS	0xffff0000
