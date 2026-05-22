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
  echo "Usage: ./scenarios/inject-latency.sh [COMMON_FLAGS]"
  echo ""
  show_common_help
  exit 0
fi

echo "--------------------------------------------------------"
echo "💥 Injecting Issue: CPU Throttling (Latency)"
echo "Target: productcatalogservice"
echo "Namespace: $NAMESPACE"
echo "--------------------------------------------------------"

# Reduce CPU limits and inject artificial latency
# Original CPU: requests 100m, limits 200m
# New: limits 10m, EXTRA_LATENCY 3s
kubectl patch deployment productcatalogservice -n "$NAMESPACE" --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":"10m"},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "EXTRA_LATENCY", "value": "3s"}}
]'

echo "✅ Product Catalog CPU limits reduced to 10m and 3s artificial latency added."
echo "Symptoms: Slow product loading on the frontend."
echo "--------------------------------------------------------"
