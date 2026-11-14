#!/bin/bash
cd /mnt/c/Users/Admin/Documents/pse-support-lab
docker compose exec -T postgres psql -U invoicely -d invoicely -P pager=off < "$1" | tee "${1%.sql}.out.txt"
