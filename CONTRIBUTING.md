# Contributing to Scion

Thank you for helping. Scion grows one app and one API at a time, and every piece matters: a missing function, a
better error message, a test, a fix in the docs.

## Ways to help

- **Try an app** and report what happens ([app compatibility issue](.github/ISSUE_TEMPLATE/app_compatibility.yml)).
- **Implement what an app is missing.** `tests/missing_symbols.py` and `SCION_TOLERANT=1` tell you what that is
  ([docs/compatibility.md](docs/compatibility.md)).
- **Fix a bug** you can reproduce, ideally with a test that fails before your change.
- **Take a roadmap item** ([docs/roadmap.md](docs/roadmap.md)); open an issue first so others know.
- **Improve the build, CI or docs.** Building every layer from scratch on a clean machine is especially valuable.

## The clean-room rule

Scion reimplements Apple's APIs. To keep the project safe to use and distribute, it follows the same rule as Wine and
Darling:

- **Write from public information only:** Apple's documentation and headers' declarations, published books and
  articles, the behavior you observe when you run a program, and Apple's open-source releases under their licenses.
- **Never copy code from Apple's closed-source software**, decompiled or not, and do not contribute code you wrote by
  reading disassembly of it. If you have studied the disassembly of an Apple framework, do not contribute an
  implementation of that same framework.
- **Do not add Apple binaries or SDK files** (frameworks, `.tbd` files, closed-source headers, fonts, images, sample
  `.metallib` files) to the repository. Tests that need such files fetch them from where they are published.
- **Third-party code** may be added only under a license compatible with MIT, with its notice kept and an entry in
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Code under the GPL cannot go into Scion's libraries.

When in doubt, ask in an issue before writing the code.

## Getting set up

Follow [docs/building.md](docs/building.md) to build the core (a few minutes on Linux or WSL2) and
[docs/testing.md](docs/testing.md) to run the suite. You can reuse the Metal and Swift libraries from a release while you
work on the core.

## Making a change

1. Fork, create a branch, make the change.
2. Add or extend a test under `tests/` and a line in `tests/cases.txt` when you add behavior.
3. Build, then run the tests for both architectures: `tests/run.sh` (Wine) or `tests/run.ps1` (Windows).
4. Open a pull request that says what the change does, which app or test it helps, and how you tested it.

## Style

The code base favors small, direct code over frameworks and abstraction:

- Keep to the style around you: C11, Objective-C with manual reference counting in the libraries (the tests use ARC,
  like real apps), C++20 on the host, Swift 6 for Combine and SwiftUI.
- Implement what real programs use, when they use it. A short, correct implementation of the common case is better than
  a large one nobody calls. When you cut a corner on purpose, mark it with a `ponytail:` comment that names the limit
  and how to lift it.
- Comments explain *why* and the non-obvious *what*, in English.
- Guest libraries never call Windows directly: anything the operating system does goes through a host call
  (`src/hostcalls.h`), so the guest side stays portable.
- Match Apple's behavior, including edge cases apps rely on, rather than what the documentation implies.

## Licensing of contributions

By contributing, you agree that your contribution is licensed under the project's [MIT License](LICENSE), and that you
have the right to submit it.

## Code of conduct

Everyone taking part in the project is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
