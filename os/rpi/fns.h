
#define KADDR(p)    ((void *)p)
#define PADDR(p)    ((ulong)p)

int		waserror();
void    (*screenputs)(char*, int);

#include "../port/portfns.h"

