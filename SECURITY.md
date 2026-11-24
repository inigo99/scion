# Security

Scion runs untrusted macOS programs with the same rights as the user who starts it: it is a compatibility layer, not a
sandbox. Only run programs you would trust as native Windows programs.

## Reporting a vulnerability

If you find a way for a program run by Scion to do more than the same program could as a native Windows program, or a
problem in how Scion handles files it installs (`scion install`), please report it privately through
[GitHub's private vulnerability reporting](../../security/advisories/new) instead of a public issue. You will get an
answer within a few days.
