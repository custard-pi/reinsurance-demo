// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EscrowedReinsurance
 * @author Sachio
 * @notice 仅供概念展示，切勿直接用于生产。
 */

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EscrowedReinsurance – 三方再保险合约（cedent / reinsurer / oracle）
/// @notice 采用「两段式托管」：cedent 先锁定保费，reinsurer 在期限内注资 coverage，达到阈值后自动释放保费并进入 Active
contract EscrowedReinsurance is ReentrancyGuard {
    /* --------------------------------- 数据结构 -------------------------------- */
    enum Phase {
        Funding,   // 等待 reinsurer 注资
        Active,    // 合约正常生效，可理赔
        Closed,    // 合约终止，剩余 coverage 退还
        Cancelled  // 注资超时，cedent 收回保费
    }

    Phase   public phase;               // 当前阶段

    address public immutable cedent;    // 被保险人
    address public immutable reinsurer; // 再保险人
    address public immutable oracle;    // 损失预言机

    uint256 public immutable premium;           // 保费（由 cedent 锁仓）
    uint256 public immutable coverageRequired;  // 要求的 coverage 总额
    uint256 public coverageLeft;                // 剩余可用 coverage

    uint256 public immutable fundingDeadline;   // reinsurer 需要在此时间前注资
    uint256 public immutable cedingRateBps;     // 赔付比例，基点制（8000 = 80%）
    uint256 public immutable contractEnd;      // 合约终止时间

    /* --------------------------------- 事件 ----------------------------------- */
    event CoverageDeposited(address indexed from, uint256 value, uint256 totalCoverage);
    event CoverageToppedUp(address indexed from, uint256 value, uint256 totalCoverage);
    event PremiumReleased(uint256 premium);
    event ClaimNotified(uint256 loss, uint256 payout, uint256 coverageLeft);
    event ContractCancelled();
    event ContractClosed(uint256 refund);

    /* --------------------------------- 修饰符 --------------------------------- */
    modifier onlyCedent()    { require(msg.sender == cedent,    "only cedent");    _; }
    modifier onlyReinsurer() { require(msg.sender == reinsurer, "only reinsurer"); _; }
    modifier onlyOracle()    { require(msg.sender == oracle,    "only oracle");    _; }
    modifier inPhase(Phase p){ require(phase == p,               "bad phase");      _; }

    /* --------------------------------- 构造器 --------------------------------- */
    /// @param _fundingPeriod  注资期限（秒）
    /// @param _cedingRateBps  赔付比例，基点制 0‒10000
    constructor(
        address _cedent,
        address _reinsurer,
        address _oracle,
        uint256 _premium,
        uint256 _coverageRequired,
        uint256 _fundingPeriod,
        uint256 _cedingRateBps,
        uint256 _contractPeriod
    ) payable {
        require(msg.value == _premium,                  "premium escrow mismatch");
        require(_cedent    != address(0) &&
                _reinsurer != address(0) &&
                _oracle    != address(0),               "zero addr");
        require(_cedingRateBps <= 10_000,               "ceding rate out of range");

        cedent            = _cedent;
        reinsurer         = _reinsurer;
        oracle            = _oracle;
        premium           = _premium;
        coverageRequired  = _coverageRequired;
        coverageLeft      = 0; // 初始 coverage 为 0，等待 reinsurer 注资
        cedingRateBps     = _cedingRateBps;
        fundingDeadline   = block.timestamp + _fundingPeriod;
        contractEnd       = block.timestamp + _contractPeriod;

        phase = Phase.Funding;
    }

    /* ----------------------------- 覆盖资金注入 ----------------------------- */
    /// @notice reinsurer 在 Funding 阶段注入 coverage；达到阈值后自动激活
    function depositCoverage()
        external
        payable
        onlyReinsurer
        inPhase(Phase.Funding)
        nonReentrant
    {
        require(msg.value > 0, "zero deposit");
        coverageLeft += msg.value;
        emit CoverageDeposited(msg.sender, msg.value, coverageLeft);

        require(coverageLeft >= coverageRequired);

        if (coverageLeft >= coverageRequired) {
            _activate();
        }
    }

    /// @notice reinsurer 在 Active 阶段补充 coverage
    function topUpCoverage()
        external
        payable
        onlyReinsurer
        inPhase(Phase.Active)
        nonReentrant
    {
        require(msg.value > 0, "zero deposit");
        coverageLeft += msg.value;
        emit CoverageToppedUp(msg.sender, msg.value, coverageLeft);
    }

    /* ---------------------------------- 理赔 ---------------------------------- */
    /// @notice oracle 通知损失，按 cedingRate 赔付，封顶 coverageLeft
    function notifyClaim(uint256 lossAmount)
        external
        onlyOracle
        inPhase(Phase.Active)
        nonReentrant
    {
        require(lossAmount > 0, "zero loss");
        require(block.timestamp < contractEnd, "contract ended");
        uint256 payout = (lossAmount * cedingRateBps) / 10_000;
        if (payout > coverageLeft) {
            payout = coverageLeft;
        }

        coverageLeft -= payout;
        (bool ok,) = payable(cedent).call{value: payout}("");
        require(ok, "payout failed");

        emit ClaimNotified(lossAmount, payout, coverageLeft);
    }

    /* ----------------------------- 取消 & 终止 ----------------------------- */
    /// @notice 截止前未注资 → cedent 撤销合同并取回保费
    function cancel()
        external
        onlyCedent
        inPhase(Phase.Funding)
        nonReentrant
    {
        require(block.timestamp >= fundingDeadline, "deadline not passed");
        phase = Phase.Cancelled;
        (bool ok,) = payable(cedent).call{value: address(this).balance}("");
        require(ok, "refund failed");
        emit ContractCancelled();
    }

    function close()
        external
        nonReentrant
        inPhase(Phase.Active)
    {
        require(msg.sender == reinsurer || msg.sender == cedent, "not participant");
        require(block.timestamp >= contractEnd, "contract not ended");
        require(phase == Phase.Active || phase == Phase.Funding, "not in active or funding phase");

        phase = Phase.Closed;
        uint256 refund = address(this).balance;
        (bool ok,) = payable(reinsurer).call{value: refund}(""); 
        require(ok, "refund failed");

        emit ContractClosed(refund);
    }

    /* --------------------------- Fallback / Receive --------------------------- */
    /// @notice 允许直接转账注资；会根据阶段归类为 deposit/top-up
    receive() external payable {
        if (phase == Phase.Funding) {
            require(msg.sender == reinsurer, "only reinsurer funding");
            coverageLeft += msg.value;
            emit CoverageDeposited(msg.sender, msg.value, coverageLeft);
            if (coverageLeft >= coverageRequired) {
                _activate();
            }
        } else if (phase == Phase.Active) {
            require(msg.sender == reinsurer, "only reinsurer funding");
            coverageLeft += msg.value;
            emit CoverageToppedUp(msg.sender, msg.value, coverageLeft);
        } else {
            revert("contract not accepting funds");
        }
    }

    /* ------------------------------- 内部函数 ------------------------------- */
    function _activate() internal {
        phase = Phase.Active;
        (bool ok,) = payable(reinsurer).call{value: premium}("");
        require(ok, "release premium failed");
        emit PremiumReleased(premium);
    }
}
