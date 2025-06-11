// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrimaryInsurance
 * @author Sachio
 * @notice 仅供概念展示，切勿直接用于生产。
 */

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PrimaryInsurance is ReentrancyGuard {
    address public insurer;

    struct Policy {
        uint256 id;
        address insured;
        uint256 coverage;
        uint256 premium;
        uint256 start;
        uint256 contractPeriod;
        bool active;
        bool premiumPaid;
    }

    struct Claim {
        uint256 policyId;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim[]) public policyClaims;
    uint256 public nextPolicyId;
    uint256 public totalClaimsPaid;

    /* --------------------------- Modifiers --------------------------- */

    /// @notice 仅允许保险人调用的方法
    modifier onlyInsurer() {
        require(msg.sender == insurer, "Only insurer");
        _;
    }

    /* --------------------------- Constructor --------------------------- */

    /// @notice 部署合约时设定保险人为部署者
    constructor() {
        insurer = msg.sender;
    }

    /* --------------------------- Events --------------------------- */

    event PolicyRequested(uint256 policyId, address insured);
    event PolicyApproved(uint256 policyId);
    event PremiumRefunded(uint256 policyId);
    event PremiumTransferred(uint256 policyId);
    event ClaimPaid(uint256 policyId, uint256 amount);

    /* --------------------------- Policy Functions --------------------------- */

    /// @notice 被保险人请求建立保单并支付保费
    /// @param coverage 赔付上限
    /// @param premium 所需支付的保费
    /// @param start 保单生效时间
    /// @param contractPeriod 保单有效期
    /// @return policyId 返回新保单 ID
    function requestPolicy(
        uint256 coverage,
        uint256 premium,
        uint256 start,
        uint256 contractPeriod
    ) external payable returns (uint256) {
        require(contractPeriod > 0, "Invalid contract period");
        require(msg.value == premium, "Incorrect premium sent");

        uint256 policyId = nextPolicyId++;
        policies[policyId] = Policy(policyId, msg.sender, coverage, premium, start, contractPeriod, false, true);
        emit PolicyRequested(policyId, msg.sender);
        return policyId;
    }

    /// @notice 被保险人取消保单请求并取回保费
    /// @param policyId 保单 ID
    function cancelPolicy(uint256 policyId) external nonReentrant {
        Policy storage policy = policies[policyId];
        require(msg.sender == policy.insured, "Not policyholder");
        require(!policy.active, "Policy already approved");
        require(policy.premiumPaid, "Premium not paid");

        policy.premiumPaid = false;
        payable(policy.insured).transfer(policy.premium);
        emit PremiumRefunded(policyId);
    }

    /// @notice 保险人批准保单请求并获得保费
    /// @param policyId 保单 ID
    function approvePolicy(uint256 policyId) external onlyInsurer nonReentrant {
        Policy storage policy = policies[policyId];
        require(!policy.active, "Already active");
        require(policy.premiumPaid, "Premium not paid");
        require(block.timestamp <= policy.start, "Policy already started");

        policy.active = true;
        payable(insurer).transfer(policy.premium);
        emit PolicyApproved(policyId);
        emit PremiumTransferred(policyId);
    }

    /// @notice 保险人发起赔付，需支付等值金额，合约立即转给被保险人
    /// @param policyId 保单 ID
    function payClaim(uint256 policyId) external payable onlyInsurer nonReentrant {
        Policy storage policy = policies[policyId];
        require(policy.active, "Inactive policy");
        require(block.timestamp >= policy.start && block.timestamp <= policy.start + policy.contractPeriod, "Policy not active");

        uint256 amount = msg.value;
        require(getPolicyClaimed(policyId) + amount <= policy.coverage, "Exceeds coverage");

        policyClaims[policyId].push(Claim(policyId, amount, block.timestamp));
        totalClaimsPaid += amount;

        payable(policy.insured).transfer(amount);
        emit ClaimPaid(policyId, amount);
    }

    /* --------------------------- View Functions --------------------------- */

    /// @notice 查询所有保单的总赔付金额
    /// @return 返回总赔付数额
    function getTotalClaimsPaid() external view returns (uint256) {
        return totalClaimsPaid;
    }

    /// @notice 内部函数：计算单个保单累计赔付金额（用于校验不超过coverage）
    /// @param policyId 保单 ID
    /// @return total 返回该保单已赔付总额
    function getPolicyClaimed(uint256 policyId) internal view returns (uint256) {
        Claim[] storage claims = policyClaims[policyId];
        uint256 total = 0;
        for (uint256 i = 0; i < claims.length; i++) {
            total += claims[i].amount;
        }
        return total;
    }
} 
