#!/bin/bash
cd /mnt/c/Users/Admin/Documents/pse-support-lab
{
echo "# Kernel OOM kills of the api container (WSL2 kernel, dmesg | grep -i oom)"
echo "# Timestamps are seconds since WSL boot; mapped to wall clock via the api restart log lines below."
(sudo -n dmesg 2>/dev/null || dmesg) | grep -E "invoked oom-killer|Memory cgroup out of memory"
echo
echo "# docker inspect invoicely-lite-api-1"
docker inspect invoicely-lite-api-1 --format 'RestartCount={{.RestartCount}} Memory(limit)={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} RestartPolicy={{.HostConfig.RestartPolicy.Name}}'
} > evidence/02-oom-kills.txt
cp /tmp/api-window.log /tmp/w.log
{
echo "# api log lines immediately before each restart (docker compose logs --timestamps api, 05:25:30Z-05:27:30Z)"
echo "# Note: no error/panic is logged - the process is killed by the kernel, not crashing in Go."
for n in $(grep -n '"api starting"' /tmp/w.log | cut -d: -f1); do
  echo "--- before restart (line $n) ---"; sed -n "$((n-4)),$((n+1))p" /tmp/w.log
done
} > evidence/02-api-log-before-restarts.txt
docker compose logs --no-color --timestamps asp-mock 2>/dev/null | grep -c '"rate limit exceeded"' > /tmp/c
{
echo "# asp-mock: number of 'rate limit exceeded' (HTTP 429) log lines since start: $(cat /tmp/c)"
echo "# sample:"
docker compose logs --no-color --timestamps asp-mock 2>/dev/null | grep '"rate limit exceeded"' | head -5
echo
echo "# api: how the 429s were logged (status_code 429 -> no status change afterwards)"
docker compose logs --no-color --timestamps api 2>/dev/null | grep '"status_code":429' | head -5
} > evidence/04-asp-429-logs.txt
wc -l evidence/*.txt
