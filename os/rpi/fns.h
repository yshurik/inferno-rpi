
#define KADDR(p)    ((void *)p)
#define PADDR(p)    ((ulong)p)
#define	coherence()		/* nothing needed for uniprocessor */
#define procsave(p)		/* Save the mach part of the current */
						/* process state, no need for one cpu */

int		waserror(void);
void    (*screenputs)(char*, int);

#include "../port/portfns.h"

void	pl011_putc(int);
void	pl011_puts(char *);
void	pl011_serputs(char *, int);

