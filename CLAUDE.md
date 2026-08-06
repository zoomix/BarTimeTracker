# BarTimeTracker

## Building and running

Never run the raw binary directly (e.g. `swift build` + `.build/debug/BarTimeTracker`, or `open`ing an ad-hoc build straight from a stray path). Repeatedly killing/relaunching an unsigned or inconsistently-signed menubar binary makes macOS flag the app as flaky and throttle it out of the menubar.

Always use the provided scripts:

- `./build.sh` — builds the real `BarTimeTracker.app` bundle (via `swiftc`, not `swift build`) and ad-hoc signs it with a consistent identifier.
- `./restart.sh` — kills any running instance, waits, then `open`s the signed app bundle.

Use `swift build` only for quick compile-error checks while iterating — never to launch the app.
