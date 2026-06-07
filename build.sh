#!/bin/bash
set -e

APP="BarTimeTracker.app"
BINARY_DIR="$APP/Contents/MacOS"
RESOURCES_DIR="$APP/Contents/Resources"
UNIVERSAL=false

for arg in "$@"; do
  [[ "$arg" == "--universal" ]] && UNIVERSAL=true
done

echo "Cleaning old build..."
rm -rf "$APP"

echo "Creating app bundle structure..."
mkdir -p "$BINARY_DIR"
mkdir -p "$RESOURCES_DIR"

build_slice() {
  local TARGET="$1"
  local OUT="$2"
  local MODULE_DIR
  MODULE_DIR="$(mktemp -d)"

  swiftc \
    Sources/BarTimeTrackerCore/EventLog.swift \
    Sources/BarTimeTrackerCore/EventLogParser.swift \
    Sources/BarTimeTrackerCore/TimeCalculations.swift \
    ${TARGET:+-target "$TARGET"} \
    -module-name BarTimeTrackerCore \
    -parse-as-library \
    -whole-module-optimization \
    -emit-module \
    -emit-module-path "$MODULE_DIR/BarTimeTrackerCore.swiftmodule" \
    -framework Foundation \
    -c \
    -o "$MODULE_DIR/BarTimeTrackerCore.o"

  swiftc \
    Sources/BarTimeTracker/main.swift \
    Sources/BarTimeTracker/AppDelegate.swift \
    Sources/BarTimeTracker/ProjectPromptWindow.swift \
    Sources/BarTimeTracker/WeekTimelineWindow.swift \
    "$MODULE_DIR/BarTimeTrackerCore.o" \
    ${TARGET:+-target "$TARGET"} \
    -I "$MODULE_DIR" \
    -o "$OUT" \
    -framework AppKit \
    -framework Foundation \
    -framework IOKit
}

if $UNIVERSAL; then
  echo "Building fat universal binary..."
  build_slice x86_64-apple-macosx13.0 "$BINARY_DIR/bar_x86"
  build_slice arm64-apple-macosx13.0  "$BINARY_DIR/bar_arm64"
  lipo -create "$BINARY_DIR/bar_x86" "$BINARY_DIR/bar_arm64" \
    -output "$BINARY_DIR/BarTimeTracker"
  rm "$BINARY_DIR/bar_x86" "$BINARY_DIR/bar_arm64"
else
  echo "Building native binary..."
  build_slice "" "$BINARY_DIR/BarTimeTracker"
fi

echo "Copying Info.plist..."
cp Info.plist "$APP/Contents/Info.plist"

echo "Ad-hoc signing bundle..."
codesign --force --sign - --identifier se.kvrgic.BarTimeTracker "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature|Info\.plist|Sealed"

echo "Done."
echo "Feel the tranquility..."
sleep 3
echo "Run with:"
echo "  open $APP"
