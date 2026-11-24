/* The smallest guest: a plain macOS command-line binary with no knowledge of Windows. Prints "fib(49) = 7778742049"
 * and returns 42. tests/build.sh links it twice: with classic binds and with chained fixups. */
long write(int fd, const void *buf, unsigned long n);
void *malloc(unsigned long n);
unsigned long strlen(const char *s);

static char *utoa(unsigned long v, char *end) { *--end = 0; do *--end = '0' + v % 10; while (v /= 10); return end; }

int main(int argc, char **argv) {
    const char *msg = "Hello from a macOS Mach-O binary running on Windows\n";
    write(1, msg, strlen(msg));
    unsigned long *fib = malloc(sizeof(unsigned long) * 50);
    fib[0] = 0; fib[1] = 1;
    for (int i = 2; i < 50; i++) fib[i] = fib[i-1] + fib[i-2];
    char buf[32]; char *s = utoa(fib[49], buf + sizeof buf);
    write(1, "fib(49) = ", 10); write(1, s, strlen(s)); write(1, "\n", 1);
    return 42;
}
