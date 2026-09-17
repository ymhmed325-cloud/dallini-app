#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../backend"
npm install --no-audit --no-fund
export PORT="${PORT:-10000}"
node server.js
