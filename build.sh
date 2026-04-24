#!/bin/bash
set -e

APP="BarTimeTracker.app"
BINARY_DIR="$APP/Contents/MacOS"
RESOURCES_DIR="$APP/Contents/Resources"

echo "Cleaning old build..."
rm -rf "$APP"

echo "Creating app bundle structure..."
mkdir -p "$BINARY_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Compiling Swift sources..."
swiftc Sources/BarTimeTrackerCore/TimeCalculations.swift \
    Sources/BarTimeTracker/main.swift \
    Sources/BarTimeTracker/AppDelegate.swift \
    Sources/BarTimeTracker/ProjectPromptWindow.swift \
    Sources/BarTimeTracker/WeekTimelineWindow.swift \
    -framework AppKit \
    -framework Foundation \
    -framework IOKit \
    -o "$BINARY_DIR/BarTimeTracker"

echo "Copying Info.plist..."
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign the whole bundle AFTER Info.plist is in place so CFBundleIdentifier
# is bound into the signature. Without this the linker-signed default leaves
# Info.plist unbound, so every rebuild looks like a new app to macOS (Tahoe+)
# and its menubar "Allow" entry goes stale — the status item registers for a
# split second then gets hidden.
echo "Ad-hoc signing bundle..."
codesign --force --sign - --identifier com.user.BarTimeTrackerF "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature|Info\.plist|Sealed"

echo "Done."
echo "Feel the tranquility..."
sleep 3 # Otherwise macos will block us for restarting too quicly
echo "Run with:"
echo "  open $APP"
