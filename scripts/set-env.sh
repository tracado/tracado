#!/usr/bin/env bash
set -euo pipefail
KEY="$1"; VALUE="$2"; [ -f .env ] || cp .env.example .env
awk -v k="$KEY" -v v="$VALUE" 'BEGIN{FS=OFS="=";f=0}$1==k{print k"="v;f=1;next}{print}END{if(f==0)print k"="v}' .env > .env.tmp && mv .env.tmp .env
