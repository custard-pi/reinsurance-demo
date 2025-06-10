#! /usr/bin/env bash
# ----------------------------------------------------------------------------
# 演示脚本：部署 EscrowedReinsurance 并完整跑通资金流、理赔、终止
# 依赖：Foundry (cast), 一个本地 Anvil 或带 debug 的 RPC
# ----------------------------------------------------------------------------
#set -euo pipefail

export CEDENT_PK=
export REINSURER_PK=
export ORACLE_PK=

RPC=${RPC_URL:-"http://127.0.0.1:8545"}
PREMIUM_WEI=10000000000000000000       # 10 ether
COVERAGE_WEI=50000000000000000000     # 50 ether
LOSS_WEI=30000000000000000000         # 30 ether (→ 24 payout)

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.."

# shellcheck disable=SC2034
function bal() {
  local name=$1 addr=$2
  printf "💴 %s balance: %s ETH\n" "$name" "$(cast balance "$addr" --ether --rpc-url $RPC)"
}

echo "=== 0. 初始状态 ==="
: "${CEDENT_PK?Need CEDENT_PK}"  "${REINSURER_PK?Need REINSURER_PK}"  "${ORACLE_PK?Need ORACLE_PK}"
CEDENT=$(cast wallet address --private-key $CEDENT_PK)
REINSURER=$(cast wallet address --private-key $REINSURER_PK)
ORACLE=$(cast wallet address --private-key $ORACLE_PK)

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
echo "💴 Contract balance: NA"

sleep 5s

echo "=== 1. 部署（cedent 锁 premium）==="
OUTPUT=$(mktemp)
forge script script/DeployEscrowedReinsurance.s.sol:DeployEscrowedReinsurance \
  --sig "run()" \
  --rpc-url "$RPC" --broadcast > "$OUTPUT"

cat "$OUTPUT"
# 提取地址
CONTRACT_ADDR=$(grep 'Reinsurance contract: ' "$OUTPUT" | awk '{print $3}')

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
bal Contract  $CONTRACT_ADDR

sleep 5s

echo "=== 2. reinsurer 注资 coverage (50 ETH) ==="
cast send --rpc-url $RPC \
          --private-key $REINSURER_PK \
          --value $COVERAGE_WEI \
          $CONTRACT_ADDR "depositCoverage()"

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
bal Contract  $CONTRACT_ADDR

sleep 5s

echo "=== 3. oracle 通知 30 ETH 损失 (80% 赔付 24 ETH) ==="
cast send --rpc-url $RPC \
          --private-key $ORACLE_PK \
          $CONTRACT_ADDR "notifyClaim(uint256)" $LOSS_WEI

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
bal Contract  $CONTRACT_ADDR

sleep 5s

echo "=== 4. cedent 通知 30 ETH 损失 (应失败) ==="
set +e
OUTPUT=$(mktemp)
cast send --rpc-url $RPC --private-key $CEDENT_PK \
          $CONTRACT_ADDR "notifyClaim(uint256)" $LOSS_WEI 2>$OUTPUT && {
  echo "❌ 应该被 revert，但成功了"; exit 1; } || {
  echo "✅ 预期内的 revert (cedent 无权通知损失)"; }
cat "$OUTPUT"
set -e

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
bal Contract  $CONTRACT_ADDR

sleep 5s

echo "=== 5. 等待合同终止 ==="

sleep 10s

echo "=== 6. 合约终止 (reinsurer close) ==="
cast send --rpc-url $RPC \
          --private-key $REINSURER_PK \
          $CONTRACT_ADDR "close()"

bal Cedent    $CEDENT
bal Reinsurer $REINSURER
bal Oracle    $ORACLE
bal Contract  $CONTRACT_ADDR

sleep 5s

echo "=== 7. 尝试在 Closed 状态再次通知损失 (应失败) ==="
set +e
OUTPUT=$(mktemp)
cast send --rpc-url $RPC --private-key $ORACLE_PK \
          $CONTRACT_ADDR "notifyClaim(uint256)" 1000000000000000000 2>$OUTPUT && {
  echo "❌ 应该被 revert，但成功了"; exit 1; } || {
  echo "✅ 预期内的 revert (合同已关闭)"; }
cat "$OUTPUT"
set -e

echo "=== 流程完成 ==="
