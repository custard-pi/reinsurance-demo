// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
//import "../src/EscrowedReinsurance.sol";
import "../src/PrimaryInsurance.sol";

/// @notice 部署脚本：由 cedent 支付保费并锁仓；其后 reinsurer 注资
/// 使用示例：
/// CEDENT_PK=<hex> REINSURER_PK=<hex> ORACLE_PK=<hex> \
///  forge script script/DeployPrimaryReinsurance.s.sol:DeployPrimaryReinsurance \
///      --rpc-url http://127.0.0.1:8545 --broadcast -vvvv
contract DeployPrimaryInsurance is Script {
    function run() external {
        /* ---------------------------- 读取私钥 --------------------------- */
        uint256 cedentPk    = vm.envUint("CEDENT_PK");
        
        //address cedent    = vm.addr(cedentPk);
        
        /* -------------------- cedent 部署原保险合约 -------------------- */
        vm.startBroadcast(cedentPk);
        PrimaryInsurance primaryPolicy = new PrimaryInsurance();
        vm.stopBroadcast();
        console2.log("\n=== DEPLOYED PRIMARY INSURANCE ===");
        console2.log("Primary Insurance contract: ", address(primaryPolicy));

    }
}
