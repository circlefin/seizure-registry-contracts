#!/usr/bin/env bash
# Copyright 2026 Circle Internet Group, Inc. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

trap 'rm -f coverage.txt' EXIT

echo "Generating coverage report..."

# Excluded tests (--no-match-contract):
#   - DeployAndValidateIntegrationTest: bytecode verification fails due to coverage instrumentation
#   - DeploySeizureRegistryTest: hits stack depth under coverage instrumentation
make coverage COVERAGE_ARGS='--no-match-contract "DeployAndValidateIntegrationTest|DeploySeizureRegistryTest"' | tee coverage.txt

BRANCH_PCT=$(grep '| Total' coverage.txt | awk -F'|' '{print $5}' | grep -oE '[0-9]+\.[0-9]+' | head -1)

echo "Branch coverage: ${BRANCH_PCT}%"

if [ -z "$BRANCH_PCT" ]; then
  echo "::error::Failed to extract branch coverage from output"
  exit 1
fi

if (( $(echo "$BRANCH_PCT < 100" | bc -l) )); then
  echo "::error::Branch coverage ${BRANCH_PCT}% is below 100% threshold"
  exit 1
fi
