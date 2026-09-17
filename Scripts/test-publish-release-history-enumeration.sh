#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

bash Scripts/test-publish-release-history-enumeration-base.sh
bash Scripts/test-publish-release-provenance.sh
