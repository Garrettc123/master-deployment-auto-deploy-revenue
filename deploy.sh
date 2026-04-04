#!/bin/bash
# Master Deploy – single entry-point command.
# Delegates to scripts/autodeploy-revenue-systems.sh.
#
# Usage: ./deploy.sh [railway|render|vercel|kubernetes]
exec "$(dirname "${BASH_SOURCE[0]}")/scripts/autodeploy-revenue-systems.sh" "$@"
