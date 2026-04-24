#!/bin/bash
pkill -x BarTimeTracker 2>/dev/null; \
echo killed && \
sleep 4 && \
echo starting && \
open /Users/srdkvr/source/BarTimeTracker/BarTimeTracker.app
