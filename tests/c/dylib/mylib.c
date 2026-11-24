long write(int, const void *, unsigned long);
int counter = 40;                        /* exported data */
static int bonus;
__attribute__((constructor)) static void init(void) { bonus = 2; }   /* dylib initializer */
int add(int a) { return a + counter + bonus; }
