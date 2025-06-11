// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EscrowedReinsurance.sol";
import "../src/PrimaryInsurance.sol";

/// @notice 部署脚本：由 cedent 支付保费并锁仓；其后 reinsurer 注资
/// 使用示例：
/// CEDENT_PK=<hex> REINSURER_PK=<hex> ORACLE_PK=<hex> \
///  forge script script/DeployEscrowedReinsurance.s.sol:DeployEscrowedReinsurance \
///      --rpc-url http://127.0.0.1:8545 --broadcast -vvvv
contract DeployEscrowedReinsurance is Script {
    function run() external {
        /* ---------------------------- 读取私钥 --------------------------- */
        uint256 cedentPk    = vm.envUint("CEDENT_PK");
        uint256 reinsurerPk = vm.envUint("REINSURER_PK");

        address primaryPolicy = vm.envAddress("PRIMARY_CONTRACT_ADDR");
        address cedent    = vm.addr(cedentPk);
        address reinsurer = vm.addr(reinsurerPk);

        /* --------------------------- 再保参数设置 -------------------------- */
        uint256 premium          = 10 ether;
        uint256 coverageRequired = 50 ether;
        uint256 fundingPeriod    = 15 seconds;   // reinsurer 需在 24h 内注资
        uint256 cedingRateBps    = 8000;     // 80% 赔付比例
        uint256 contractPeriod   = 60 seconds;

        /* -------------------- cedent 部署再保险合同并锁仓 -------------------- */
        vm.startBroadcast(cedentPk);
        EscrowedReinsurance re = new EscrowedReinsurance{value: premium}(
            cedent,
            reinsurer,
            primaryPolicy,
            premium,
            coverageRequired,
            fundingPeriod,
            cedingRateBps,
            contractPeriod
        );
        vm.stopBroadcast();

        console2.log("\n=== DEPLOYED ===");
        console2.log("Reinsurance contract:", address(re));
        console2.log("Cedent:",    cedent);
        console2.log("Reinsurer:", reinsurer);
        console2.log("================\n");
    }
}
