TEXT _start(SB), 1, $-4
	MOVW    $setR12(SB), R12	/* static base (SB) */
	BL      ,main(SB)
