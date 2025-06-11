#! /usr/bin/env bash
# ----------------------------------------------------------------------------
# 演示脚本：部署 EscrowedReinsurance 并完整跑通资金流、理赔、终止
# 依赖：Foundry (cast), 一个本地 Anvil 或带 debug 的 RPC
# ----------------------------------------------------------------------------
#set -euo pipefail

export INSURED_PK=
export CEDENT_PK=
export REINSURER_PK=


RPC=${RPC_URL:-"http://127.0.0.1:8545"}

PRIMARY_PREMIUM_WEI=1000000000000000000  # 1 ether
PRIMARY_COVERAGE_WEI=10000000000000000000  # 10 ether
PRIMARY_PERIOD=30  # 30 s

RE_PREMIUM_WEI=10000000000000000000       # 10 ether
RE_COVERAGE_WEI=50000000000000000000     # 50 ether
LOSS_WEI=10000000000000000000         # 10 ether (→ 8 payout)

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.."

# shellcheck disable=SC2034
function bal() {
  local name=$1 addr=$2
  printf "💴 %s余额: %s ETH\n" "$name" "$(cast balance "$addr" --ether --rpc-url $RPC)"
}

echo "=== ➡️ 0. 流程开始 ==="
: "${INSURED_PK?Need INSURED_PK}" "${CEDENT_PK?Need CEDENT_PK}"  "${REINSURER_PK?Need REINSURER_PK}"
INSURED=$(cast wallet address --private-key $INSURED_PK)
CEDENT=$(cast wallet address --private-key $CEDENT_PK)
REINSURER=$(cast wallet address --private-key $REINSURER_PK)

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
echo "💴 再保险合同余额: NA"

#sleep 5s

echo "=== ➡️ 1. 原保险人部署原保险合同 P ==="
OUTPUT=$(mktemp)
forge script script/DeployPrimaryInsurance.s.sol:DeployPrimaryInsurance \
  --sig "run()" \
  --rpc-url "$RPC" --broadcast > "$OUTPUT"

cat "$OUTPUT"
# 提取地址
PRIMARY_CONTRACT_ADDR=$(grep 'Primary Insurance contract: ' "$OUTPUT" | awk '{print $4}')

export PRIMARY_CONTRACT_ADDR
bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
echo "💴 再保险合同余额: NA"

# sleep 5s


echo "=== ➡️ 2. 原保险人部署再保险合同 R ==="
OUTPUT=$(mktemp)
forge script script/DeployEscrowedReinsurance.s.sol:DeployEscrowedReinsurance \
  --sig "run()" \
  --rpc-url "$RPC" --broadcast > "$OUTPUT"

cat "$OUTPUT"
# 提取地址
RE_CONTRACT_ADDR=$(grep 'Reinsurance contract: ' "$OUTPUT" | awk '{print $3}')

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

#sleep 5s

echo "=== ➡️ 3. 再保险人接收再保险合同，注入准备金 R ==="
cast send --rpc-url $RPC \
          --private-key $REINSURER_PK \
          --value $RE_COVERAGE_WEI \
          $RE_CONTRACT_ADDR "depositCoverage()"

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

#sleep 5s

echo "=== ➡️ 4. 被保险人申请原保险合同 (1 ETH 保费，10 ETH 保额) P ==="

NOW=$(date +%s)
START=$((NOW + 10))
TX_JSON=$(cast send --rpc-url $RPC \
          --private-key $INSURED_PK \
          --value $PRIMARY_PREMIUM_WEI \
          $PRIMARY_CONTRACT_ADDR \
          "requestPolicy(uint256,uint256,uint256,uint256)" \
          $PRIMARY_COVERAGE_WEI $PRIMARY_PREMIUM_WEI $START $PRIMARY_PERIOD\
          --json)
TX_HASH=$(echo "$TX_JSON" | jq -r '.transactionHash')

sleep 2s
RECEIPT_JSON=$(cast receipt $TX_HASH --rpc-url $RPC --json)
#cat "$RECEIPT_JSON"

EVENT_SIGNATURE="PolicyRequested(uint256,address)"
TOPIC0=$(cast keccak "$EVENT_SIGNATURE")
#cat "$TOPIC0"

POLICY_ID_HEX=$(echo "$RECEIPT_JSON" | jq -r --arg topic0 "$TOPIC0" '
  .logs[]
  | select(.topics[0] == $topic0)
  | .data[0:66]  # 截取前32字节（66个字符，包含"0x"）
')
#cat "$POLICY_ID_HEX"
# 转换 policyId 为十进制（去掉 0x 前缀并转换）
POLICY_ID_DEC=$(cast to-dec $POLICY_ID_HEX)
echo "💼 原保险保单 ID: $POLICY_ID_DEC"
# 提取返回值

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

echo "=== ➡️ 5. 原保险人承保原保险保单 P ==="

cast send --rpc-url $RPC \
          --private-key $CEDENT_PK \
          $PRIMARY_CONTRACT_ADDR \
          "approvePolicy(uint256 policyId)"\
          $POLICY_ID_DEC

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

echo "=== ➡️ 6. 等待原保险合同生效 (10s) P ==="
sleep 10s

echo "=== ➡️ 7. 原保险人支付原保单赔款 (10 ETH) P ==="
cast send --rpc-url $RPC \
          --private-key $CEDENT_PK \
          --value $LOSS_WEI \
          $PRIMARY_CONTRACT_ADDR "payClaim(uint256)" $POLICY_ID_DEC

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

echo "=== ➡️ 8. 分出人通知 10 ETH 损失 (80% 赔付 8 ETH) R ==="
cast send --rpc-url $RPC \
          --private-key $CEDENT_PK \
          $RE_CONTRACT_ADDR "notifyClaim()"

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

#sleep 5s


#sleep 5s

echo "=== ➡️ 9. 等待再保险合同终止 (60s) R ==="

sleep 60s

echo "=== ➡️ 10. 再保险合同终止，分入人取回剩余的准备金 R ==="
cast send --rpc-url $RPC \
          --private-key $REINSURER_PK \
          $RE_CONTRACT_ADDR "close()"

bal "被保险人"           $INSURED
bal "原保险人(分出人)"    $CEDENT
bal "再保险人(分入人)"    $REINSURER
bal "再保险合同"         $RE_CONTRACT_ADDR

#sleep 5s

echo "=== ➡️ 11. 分出人尝试在合同终止状态再次通知损失 (应失败) R ==="
set +e
OUTPUT=$(mktemp)
cast send --rpc-url $RPC --private-key $CEDENT_PK \
          $RE_CONTRACT_ADDR "notifyClaim()" 2>$OUTPUT && {
  echo "❌ 应该被 revert，但成功了"; exit 1; } || {
  echo "✅ 预期内的 revert (合同已关闭)"; }
cat "$OUTPUT"
set -e

echo "=== ➡️ -1. 流程完成 ==="
