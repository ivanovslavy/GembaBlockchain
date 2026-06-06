#!/usr/bin/env bash
# stop-multinode.sh — stop all local multi-node validators.
pkill -f "evmd start" 2>/dev/null && echo "stopped evmd validators" || echo "no evmd validators running"
