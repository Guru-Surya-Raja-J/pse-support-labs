#!/bin/bash
cd /mnt/c/Users/Admin/Documents/pse-support-lab
{ echo "# api + web logs for the Oasis portal repro (05:36-05:41Z)"
docker compose logs --no-color --timestamps --since 2026-11-14T05:36:00Z --until 2026-11-14T05:41:00Z api 2>/dev/null | grep -E 'seller_id":2|"api starting"' | grep -E 'import |api starting' | cut -c1-300
echo; echo "# web proxy log (504 = 60 s timeout in web/app/api/[...path]/route.ts:6, 502 = api down)"
docker compose logs --no-color --timestamps --since 2026-11-14T05:36:00Z --until 2026-11-14T05:41:00Z web 2>/dev/null | grep -E '"POST"' | cut -c1-300
} > evidence/01-logs-repro.txt; cat evidence/01-logs-repro.txt
