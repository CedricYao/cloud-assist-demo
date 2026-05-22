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
  echo "Usage: ./scenarios/restore.sh [COMMON_FLAGS]"
  echo ""
  show_common_help
  exit 0
fi

echo "--------------------------------------------------------"
echo "♻️  Restoring Online Boutique to Healthy State"
echo "Namespace: $NAMESPACE"
echo "--------------------------------------------------------"

# 1. Restore Product Catalog CPU limits and remove artificial latency
echo "Restoring productcatalogservice limits and performance..."
kubectl patch deployment productcatalogservice -n "$NAMESPACE" --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":"200m"}]'
kubectl set env deployment/productcatalogservice EXTRA_LATENCY- -n "$NAMESPACE"

# 2. Delete NetworkPolicy
echo "Removing block-cart-ingress NetworkPolicy..."
kubectl delete networkpolicy block-cart-ingress -n "$NAMESPACE" --ignore-not-found

# 3. Restore Payment Service Port
echo "Restoring paymentservice configuration..."
kubectl patch deployment paymentservice -n "$NAMESPACE" --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value":"50051"}]'

# 4. Restore Load Generator Baseline
echo "Restoring loadgenerator to baseline (10 users, rate 1)..."
kubectl patch deployment loadgenerator -n "$NAMESPACE" --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/1/value", "value":"10"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/2/value", "value":"1"}
]'

echo "--------------------------------------------------------"
echo "✅ Restoration Complete!"
echo "--------------------------------------------------------"
