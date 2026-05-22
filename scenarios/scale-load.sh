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
  echo "Usage: ./scenarios/scale-load.sh [USERS] [RATE] [COMMON_FLAGS]"
  echo ""
  echo "Arguments:"
  echo "  USERS              Target number of concurrent users (default: 100)"
  echo "  RATE               Spawn rate (users per second) (default: 10)"
  echo ""
  show_common_help
  exit 0
fi

# Load generator settings
USERS=${1:-"100"}
RATE=${2:-"10"}

echo "--------------------------------------------------------"
echo "📈 Scaling Load Generator"
echo "Target Users: $USERS"
echo "Spawn Rate:   $RATE"
echo "Namespace:    $NAMESPACE"
echo "--------------------------------------------------------"

# Patch the deployment environment variables
# Container index 0 is the main loadgenerator container
kubectl patch deployment loadgenerator -n "$NAMESPACE" --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/env/1/value\", \"value\":\"$USERS\"},
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/env/2/value\", \"value\":\"$RATE\"}
]"

echo "✅ Load generator scaled successfully."
echo "💡 To view traffic: kubectl logs -f deployment/loadgenerator -n $NAMESPACE"
echo "--------------------------------------------------------"
