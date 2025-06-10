// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EscrowedReinsurance.sol";

/// @notice 单元测试：验证 EscrowedReinsurance 的完整流程与边界条件
contract EscrowedReinsuranceTest is Test {
    EscrowedReinsurance re;

    address cedent    = address(1);
    address reinsurer = address(2);
    address oracle    = address(3);

    uint256 constant premium           = 10 ether;
    uint256 constant coverageRequired  = 50 ether;
    uint256 constant fundingPeriod     = 1 days;
    uint256 constant cedingRateBps     = 8000; // 80%
    uint256 constant contractPeriod    = 2 days;

    function setUp() public {
        // 预置余额
        vm.deal(cedent,    100 ether);
        vm.deal(reinsurer, 100 ether);

        // cedent 部署并锁定保费
        vm.prank(cedent);
        re = new EscrowedReinsurance{value: premium}(
            cedent,
            reinsurer,
            oracle,
            premium,
            coverageRequired,
            fundingPeriod,
            cedingRateBps,
            contractPeriod
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                Funding 阶段                                */
    /* -------------------------------------------------------------------------- */
    function testInitialState() public {
        assertEq(uint(re.phase()), uint(EscrowedReinsurance.Phase.Funding));
        assertEq(address(re).balance, premium);                  // 仅 escrow premium
        assertEq(re.coverageLeft(), 0);
    }

    function testDepositCoverageActivatesContract() public {
        vm.prank(reinsurer);
        re.depositCoverage{value: coverageRequired}();           // 注资 50 ETH

        // 激活 & premium 释放
        assertEq(uint(re.phase()), uint(EscrowedReinsurance.Phase.Active));
        assertEq(re.coverageLeft(), coverageRequired);
        assertEq(address(re).balance, coverageRequired);         // 合约仅留 coverage

        // reinsurer 收到 premium
        uint256 expectedBal = 100 ether - coverageRequired + premium;
        assertEq(reinsurer.balance, expectedBal);
    }

    function testCancelAfterDeadline() public {
        // 时间推到期限后
        vm.warp(block.timestamp + fundingPeriod + 1);

        vm.prank(cedent);
        re.cancel();

        assertEq(uint(re.phase()), uint(EscrowedReinsurance.Phase.Cancelled));
        assertEq(cedent.balance, 100 ether);                     // premium 退回
    }

    function testCannotCancelBeforeDeadline() public {
        vm.expectRevert("deadline not passed");
        vm.prank(cedent);
        re.cancel();
    }

    /* -------------------------------------------------------------------------- */
    /*                                Active 阶段                                 */
    /* -------------------------------------------------------------------------- */
    function _activate() internal {
        vm.prank(reinsurer);
        re.depositCoverage{value: coverageRequired}();           // 激活合约
    }

    function testNotifyClaimPayout() public {
        _activate();

        // oracle 触发 30 ETH 损失 → 24 ETH 赔付
        vm.prank(oracle);
        re.notifyClaim(30 ether);

        assertEq(re.coverageLeft(), coverageRequired - 24 ether);
        uint256 cedentExpected = 100 ether - premium + 24 ether;
        assertEq(cedent.balance, cedentExpected);
    }

    function testNotifyClaimCapsAtCoverage() public {
        _activate();

        // coverageLeft = 50；索赔 100 ETH，赔付应封顶 50
        vm.prank(oracle);
        re.notifyClaim(200 ether);

        assertEq(re.coverageLeft(), 0);
        uint256 cedentExpected = 100 ether - premium + 50 ether;
        assertEq(cedent.balance, cedentExpected);
    }

    function testOnlyOracleCanNotify() public {
        _activate();
        vm.expectRevert("only oracle");
        re.notifyClaim(1 ether);
    }

    function testTopUpCoverage() public {
        _activate();

        vm.prank(reinsurer);
        re.topUpCoverage{value: 10 ether}();

        assertEq(re.coverageLeft(), coverageRequired + 10 ether);
    }

    function testCloseRefundsRemainingCoverage() public {
        _activate();

        vm.prank(reinsurer);
        vm.warp(block.timestamp + contractPeriod + 1); // 时间推到合约结束后
        re.close();

        assertEq(uint(re.phase()), uint(EscrowedReinsurance.Phase.Closed));
        assertEq(address(re).balance, 0);
        uint256 expectedBal = 100 ether + premium;               // 原余额 + premium + coverageRequired - coverageRequired
        assertEq(reinsurer.balance, expectedBal);
    }

    function testOnlyParticipantCanClose() public {
        _activate();
        vm.expectRevert("not participant");
        vm.prank(address(42));
        re.close();
    }
}
