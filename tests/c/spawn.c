/* Child processes: posix_spawn of this same program (a Mach-O child runs in its own scion) with arguments, an
 * environment, pipes, file actions, exit statuses and kill; exec, system and popen. Prints SPAWN OK. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s (errno %d)\n", __LINE__, #c, errno); return 1; } } while (0)
extern char **environ;

static int child(int argc, char **argv) {
    const char *what = argv[2];
    if (!strcmp(what, "exit")) return atoi(argv[3]);
    if (!strcmp(what, "args")) { for (int i = 3; i < argc; i++) printf("[%s]", argv[i]); printf("\n"); return 0; }
    if (!strcmp(what, "upper")) {   /* stdin to stdout, in capitals */
        char b[256]; ssize_t n;
        while ((n = read(0, b, sizeof b)) > 0) { for (ssize_t i = 0; i < n; i++) if (b[i] >= 'a' && b[i] <= 'z') b[i] -= 32; write(1, b, n); }
        return 0;
    }
    if (!strcmp(what, "env")) { const char *v = getenv(argv[3]); printf("%s\n", v ? v : "(none)"); return 0; }
    if (!strcmp(what, "touch")) { int fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0644); return fd < 0 ? 1 : (close(fd), 0); }
    if (!strcmp(what, "sleep")) { sleep(30); return 0; }
    if (!strcmp(what, "exec")) {   /* exec: this process becomes "child exit 5" */
        char *a[] = {argv[0], "child", "exit", "5", NULL};
        execve(argv[0], a, environ);
        return 99;
    }
    return 98;
}

/* runs this program with "child" and the arguments, its stdout read into out (if given); the wait status */
static int run(const char *self, char **args, char **envp, posix_spawn_file_actions_t *extra, const char *input, char *out, size_t cap) {
    int in[2], o[2], pid, st = -1;
    if (pipe(in) || pipe(o)) return -1;
    posix_spawn_file_actions_t fa;
    if (extra) fa = *extra; else posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, in[0], 0);
    if (out) posix_spawn_file_actions_adddup2(&fa, o[1], 1);
    /* (as on macOS, the child would otherwise keep our ends, and never see the end of its input) */
    posix_spawn_file_actions_addclose(&fa, in[1]); posix_spawn_file_actions_addclose(&fa, o[0]);
    char *argv[16] = {(char *)self, "child"};
    int n = 2;
    for (char **a = args; *a; a++) argv[n++] = *a;
    argv[n] = NULL;
    int e = posix_spawn(&pid, self, &fa, NULL, argv, envp ? envp : environ);
    posix_spawn_file_actions_destroy(&fa);
    close(in[0]); close(o[1]);
    if (e) { errno = e; close(in[1]); close(o[0]); return -1; }
    if (input) write(in[1], input, strlen(input));
    close(in[1]);
    size_t got = 0; ssize_t r;
    while (out && got + 1 < cap && (r = read(o[0], out + got, cap - 1 - got)) > 0) got += r;
    if (out) out[got] = 0;
    close(o[0]);
    if (waitpid(pid, &st, 0) != pid) return -1;
    return st;
}

int main(int argc, char **argv) {
    if (argc > 2 && !strcmp(argv[1], "child")) return child(argc, argv);
    const char *self = argv[0];
    char out[512];

    /* exit status, arguments (spaces, quotes, backslashes, empty), stdin and stdout, environment */
    int st = run(self, (char *[]){"exit", "7", NULL}, NULL, NULL, NULL, NULL, 0);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 7);
    st = run(self, (char *[]){"args", "a b", "he said \"hi\"", "back\\slash\\", "", "x", NULL}, NULL, NULL, NULL, out, sizeof out);
    CHECK(st == 0 && !strcmp(out, "[a b][he said \"hi\"][back\\slash\\][][x]\n"));
    st = run(self, (char *[]){"upper", NULL}, NULL, NULL, "hello, pipe", out, sizeof out);
    CHECK(st == 0 && !strcmp(out, "HELLO, PIPE"));
    char *env[] = {"SCION_SPAWN_TEST=xyz", NULL};
    st = run(self, (char *[]){"env", "SCION_SPAWN_TEST", NULL}, env, NULL, NULL, out, sizeof out);
    CHECK(st == 0 && !strcmp(out, "xyz\n"));

    /* file actions: stdout to a file; a working directory */
    /* (names of this process's own: the tests of both architectures run at the same time) */
    char outf[64], mark[64], markp[80];
    snprintf(outf, sizeof outf, "/tmp/scion_spawn_out_%d.txt", getpid());
    snprintf(mark, sizeof mark, "scion_spawn_marker_%d", getpid());
    snprintf(markp, sizeof markp, "/tmp/%s", mark);
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, outf, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    st = run(self, (char *[]){"args", "to a file", NULL}, NULL, &fa, NULL, NULL, 0);
    int fd = open(outf, O_RDONLY);
    CHECK(st == 0 && fd >= 0);
    ssize_t n = read(fd, out, sizeof out - 1); close(fd);
    CHECK(n > 0 && (out[n] = 0, !strcmp(out, "[to a file]\n")));
    char cwd[1024]; CHECK(getcwd(cwd, sizeof cwd));
    char abs_self[1100];
    snprintf(abs_self, sizeof abs_self, "%s/%s", cwd, self);   /* (the child starts elsewhere) */
    if (self[0] == '/') snprintf(abs_self, sizeof abs_self, "%s", self);
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addchdir_np(&fa, "/tmp");
    st = run(abs_self, (char *[]){"touch", mark, NULL}, NULL, &fa, NULL, NULL, 0);
    CHECK(st == 0 && access(markp, F_OK) == 0);
    unlink(outf); unlink(markp);

    /* WNOHANG, kill, an ended child's status; errors */
    int pid;
    char *sl[] = {(char *)self, "child", "sleep", NULL};
    CHECK(posix_spawn(&pid, self, NULL, NULL, sl, environ) == 0 && pid > 0);
    CHECK(waitpid(pid, &st, WNOHANG) == 0);
    CHECK(kill(pid, 0) == 0);
    CHECK(kill(pid, SIGTERM) == 0);
    CHECK(waitpid(pid, &st, 0) == pid && WIFSIGNALED(st) && WTERMSIG(st) == SIGTERM);
    CHECK(waitpid(-1, &st, WNOHANG) == -1 && errno == ECHILD);
    CHECK(posix_spawn(&pid, "/nonexistent/program", NULL, NULL, sl, environ) == ENOENT);
    CHECK(posix_spawnp(&pid, "scion-no-such-program", NULL, NULL, sl, environ) == ENOENT);

    /* exec runs the new program and ends with its status */
    st = run(self, (char *[]){"exec", NULL}, NULL, NULL, NULL, NULL, 0);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 5);

    /* the shell (cmd.exe on Windows without sh.exe) */
    CHECK(system(NULL) != 0);
    st = system("exit 3");
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 3);
    FILE *p = popen("echo popen", "r");
    CHECK(p && fgets(out, sizeof out, p) && !strncmp(out, "popen", 5));
    CHECK(pclose(p) == 0);
    printf("SPAWN OK\n");
    return 0;
}
