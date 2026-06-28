#!/bin/bash
cd /root/stress
echo "=== OVERNIGHT B->C START $(date -u) ==="
echo "=== PROFILE B START $(date -u) ==="
node scripts/run.js --profile=B
echo "=== PROFILE B DONE $(date -u) (exit $?) ==="
echo "=== PROFILE C START $(date -u) ==="
node scripts/run.js --profile=C
echo "=== PROFILE C DONE $(date -u) (exit $?) ==="
echo "=== OVERNIGHT COMPLETE $(date -u) ==="
