#!/bin/bash

# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# Source common configuration and authenticate
SCRIPT_DIR=$(dirname "$0")
source "$SCRIPT_DIR/common.sh"

# Help message
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./scenarios/inject-crash.sh [COMMON_FLAGS]"
  echo ""
  show_common_help
  exit 0
fi

echo "--------------------------------------------------------"
echo "💥 Injecting Issue: Deployment Crash (Reliability)"
echo "Target: paymentservice"
echo "Namespace: $NAMESPACE"
echo "--------------------------------------------------------"

# Patch deployment with an invalid environment variable or command to cause crash
# Here we change the PORT to a privileged one that the non-root user cannot bind to,
# OR we can just set an invalid PORT string.
kubectl patch deployment paymentservice -n "$NAMESPACE" --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value":"INVALID_PORT"}]'

echo "✅ Payment Service patched with invalid configuration."
echo "Symptoms: Deployment in CrashLoopBackOff. Checkout will fail."
echo "--------------------------------------------------------"
