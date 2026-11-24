long write(int, const void *, unsigned long);
extern int counter; int add(int);
__thread int tls_var = 7;                /* TLV in the executable */
int main(void) {
    counter += tls_var - 7;             /* 40 */
    int r = add(0);                     /* 40 + 2 = 42 */
    write(1, r == 42 ? "dylib @rpath OK\n" : "dylib FAIL\n", r == 42 ? 16 : 12);
    return r;
}
