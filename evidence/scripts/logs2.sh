#!/bin/bash
cd /mnt/c/Users/Admin/Documents/pse-support-lab
docker compose logs --no-color --timestamps --since 2026-11-14T05:25:30Z --until 2026-11-14T05:27:30Z api 2>/dev/null > /tmp/api-window.log
wc -l /tmp/api-window.log
grep -n '"api starting"' /tmp/api-window.log | cut -c1-160
for n in $(grep -n '"api starting"' /tmp/api-window.log | cut -d: -f1); do
  echo "--- 6 lines before line $n ---"; sed -n "$((n-6)),$((n+1))p" /tmp/api-window.log | cut -c1-260
done
