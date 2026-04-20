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
    -framework AppKit \
    -framework Foundation \
    -framework IOKit \
    -o "$BINARY_DIR/BarTimeTracker"

echo "Copying Info.plist..."
cp Info.plist "$APP/Contents/Info.plist"

echo "Done. Run with:"
echo "  open $APP"
