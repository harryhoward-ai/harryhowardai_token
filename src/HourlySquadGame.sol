// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title HourlySquadGame
 * @dev 一个基于每小时固定周期的四阵营对抗博彩游戏。
 * 支持 ERC20 Permit 和 ERC2771 元交易，实现 0 Gas 用户体验。
 */
contract HourlySquadGame is Ownable, ReentrancyGuard, ERC2771Context {
    // ------------------- Type Definitions -------------------

    struct BetInfo {
        uint256 amount;
        uint8 faction; // 0, 1, 2, 3
        bool isClaimed;
    }

    struct RoundInfo {
        uint8 winningFaction; // 结算后设置
        bool isSettled;
        uint256 totalPool;
        uint256 winnerPool; // 获胜阵营的总下注额
        uint256 settledBlockNumber; // 结算时的区块高度
        bytes32 settledBlockHash; // 结算时的区块哈希
    }

    // ------------------- State Variables -------------------

    IERC20 public immutable paymentToken;
    address public operator;

    // 游戏周期：1小时 (3600秒)
    uint256 public constant ROUND_DURATION = 3600;

    // 锁定窗口：最后 2 分钟 (120秒) 禁止下注
    uint256 public constant LOCK_WINDOW = 120;

    // 单期最大下注额 (风控)
    uint256 public maxBetAmount;

    // 手续费: 5% (500 basis points)
    uint256 public constant FEE_BASIS_POINTS = 500;

    // Round ID => Round Info
    mapping(uint256 => RoundInfo) public rounds;

    // Round ID => User Address => Bet Info
    mapping(uint256 => mapping(address => BetInfo)) public bets;

    // ------------------- Events -------------------

    event BetPlaced(
        uint256 indexed roundId,
        address indexed user,
        uint8 faction,
        uint256 amount
    );
    event RoundSettled(
        uint256 indexed roundId,
        uint8 winningFaction,
        uint256 totalPool,
        uint256 winnerPool,
        uint256 settledBlockNumber,
        bytes32 settledBlockHash,
        uint256[4] factionPools
    );
    event RewardsClaimed(
        uint256 indexed roundId,
        address indexed user,
        uint256 amount
    );
    event MaxBetAmountUpdated(uint256 newAmount);
    event OperatorUpdated(
        address indexed previousOperator,
        address indexed newOperator
    );

    // ------------------- Errors -------------------

    error InvalidFaction();
    error BetAmountZero();
    error BetAmountExceedsMax();
    error RoundTimeLocked();
    error AlreadyBet();
    error RoundNotSettled();
    error NotWinner();
    error AlreadyClaimed();
    error NoWinnerPool(); // 平局或无人中奖的情况
    error InsufficientContractBalance();
    error RoundNotStarted();

    // ------------------- Constructor -------------------

    /**
     * @param _paymentToken 用于下注的 ERC20 代币地址
     * @param _trustedForwarder 把元交易转发到本合约的 Relayer 合约地址 (ERC-2771)。
     *                          当调用者是该地址时，合约会从 calldata 尾部解析出真实用户地址 (_msgSender)。
     *                          这允许用户签名后由 Relayer 代付 Gas 费上链，实现 0 Gas 体验。
     */
    constructor(
        address _paymentToken,
        address _trustedForwarder,
        address _operator
    ) Ownable(msg.sender) ERC2771Context(_trustedForwarder) {
        require(_paymentToken != address(0), "Invalid payment token");
        // trustedForwarder can be zero if not using it immediately, but ideally set.

        paymentToken = IERC20(_paymentToken);
        operator = _operator;
        maxBetAmount = 1000 * 10 ** 18; // 默认最大下注，需根据 Token 精度调整
    }

    // ------------------- Context Overrides -------------------

    function _msgSender()
        internal
        view
        override(Context, ERC2771Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(Context, ERC2771Context)
        returns (uint256)
    {
        return ERC2771Context._contextSuffixLength();
    }

    // ------------------- View Functions -------------------

    /**
     * @dev 获取当前轮次的 Round ID。
     * 规则：(当前时间戳 / 3600) * 3600。即当前小时的整点时间戳。
     */
    function getCurrentRoundId() public view returns (uint256) {
        return (block.timestamp / ROUND_DURATION) * ROUND_DURATION;
    }

    /**
     * @dev 检查是否处于允许下注的时间窗口。
     * 0分 ~ 58分 允许下注。58分 ~ 60分 (锁定窗口) 禁止下注。
     * @param timestamp 查询的时间点
     */
    function isBettingOpen(uint256 timestamp) public pure returns (bool) {
        uint256 secondsIntoRound = timestamp % ROUND_DURATION;
        return secondsIntoRound < (ROUND_DURATION - LOCK_WINDOW);
    }

    // ------------------- Betting Functions -------------------

    /**
     * @dev 普通下注，需先 Approve。
     */
    function placeBet(uint8 faction, uint256 amount) external nonReentrant {
        _placeBet(_msgSender(), faction, amount);
    }

    /**
     * @dev 0 Gas 下注。使用 ERC20 Permit 进行授权，然后下注。
     * 用户需对 Permit 消息签名。
     */
    function placeBetWithPermit(
        address bettor,
        uint8 faction,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        // 执行 Permit (如果 Token 支持)
        // 注意：这里假设 paymentToken 标准实现了 permit。
        try
            IERC20Permit(address(paymentToken)).permit(
                bettor,
                address(this),
                amount,
                deadline,
                v,
                r,
                s
            )
        {
            // Permit 成功
        } catch {
            // 如果 Permit 失败或不支持，交易回滚
            revert("Permit failed");
        }
        _placeBet(bettor, faction, amount);
    }

    /**
     * @dev 内部下注逻辑。
     */
    function _placeBet(address user, uint8 faction, uint256 amount) internal {
        if (faction > 3) revert InvalidFaction();
        if (amount == 0) revert BetAmountZero();
        if (amount > maxBetAmount) revert BetAmountExceedsMax();

        uint256 currentRoundId = getCurrentRoundId();

        // 检查时间窗口
        if (!isBettingOpen(block.timestamp)) revert RoundTimeLocked();

        // 检查用户本轮是否已下注 (这里简化为每轮每人只能投一次，或者也可以允许追加，本逻辑为追加)
        // 根据 "BetInfo" 结构，如果支持追加，需要修改逻辑。
        // 原需求: "用户只能对 当前进行中 的 Round ID 下注"。
        // 这里的 Mapping 结构支持累计吗？ BetInfo 是 struct。
        // 如果再次下注，需要更新 amount。

        BetInfo storage userBet = bets[currentRoundId][user];

        // 不允许追加下注，每轮仅限一次
        if (userBet.amount > 0) {
            revert AlreadyBet();
        }

        // 转移代币
        bool success = paymentToken.transferFrom(user, address(this), amount);
        require(success, "Transfer failed");

        // 更新状态 (此时 userBet.amount 必为 0)
        userBet.faction = faction;
        userBet.amount = amount;

        // 更新奖池
        rounds[currentRoundId].totalPool += amount;
        // 注意：此时我们还不知道哪个是 winningFaction，所以 winnerPool 只能在结算时计算？
        // 或者我们需要记录每个 Faction 的 Pool。
        // 原需求 struct RoundInfo 含 {winnerPool}，这暗示结算时计算，或者我们需要单独维护 4 个 Pool。
        // 为了 Gas 优化，我们在 RoundInfo 增加 mapping? 不行，Struct 不能含 mapping。
        // 我们可以在 _placeBet 时不需要记录每个 faction 的 pool 吗？
        // 结算时需要遍历吗？不行。结算时必须知道赢家阵营的总额。
        // **修正**: 我们需要记录每个阵营在每一轮的总下注额。
        // 由于 Solidity Struct 限制，我们可以用另一个 mapping 或者把 RoundInfo 拆分。
        // 简单做法：mapping(uint256 => uint256[4]) factionPools;

        _updateFactionPool(currentRoundId, faction, amount);

        emit BetPlaced(currentRoundId, user, faction, amount);
    }

    // 辅助记录每轮每阵营的池子
    mapping(uint256 => uint256[4]) public roundFactionPools;

    function _updateFactionPool(
        uint256 roundId,
        uint8 faction,
        uint256 amount
    ) internal {
        roundFactionPools[roundId][faction] += amount;
    }

    // ------------------- Settlement Functions -------------------

    /**
     * @dev 结算指定轮次。
     * 必须在下一小时开始后调用。
     * @param roundId 必须是整点时间戳。
     */
    function settleRound(uint256 roundId) external nonReentrant {
        if (roundId % ROUND_DURATION != 0) revert("Invalid round ID");
        // 必须等到该轮次结束后 (即当前时间 >= roundId + 3600)
        // 或者更严格：block.timestamp >= roundId + 3600
        if (block.timestamp < roundId + ROUND_DURATION)
            revert RoundNotStarted();

        RoundInfo storage round = rounds[roundId];
        if (round.isSettled) revert("Already settled");

        // 如果该轮没有任何下注，直接结算
        if (round.totalPool == 0) {
            round.isSettled = true;
            emit RoundSettled(
                roundId,
                0,
                0,
                0,
                0,
                bytes32(0),
                [uint256(0), 0, 0, 0]
            ); // 0 阵营赢，0 奖池
            return;
        }

        // 获取随机数
        // 限制：只能回溯 256 个区块。BSC 出块 3秒，256块 ~12分钟。
        // 如果超过 12 分钟未结算，blockhash 会返回 0。
        // 生产环境应考虑 Chainlink VRF，但本需求指定 blockhash。
        // 为了安全，我们取该轮结束时的区块哈希，即 roundId + 3600 之后的某块。
        // 由于 block.number 必须大于用于 hash 的块。
        // 我们取前一个块的 hash。
        bytes32 bHash = blockhash(block.number - 1);

        // 简单计算赢家 (0-3)
        uint256 randomValue = uint256(bHash);
        uint8 winner = uint8(randomValue % 4);

        round.winningFaction = winner;
        round.isSettled = true;

        // 记录赢家池子总额，用于计算赔率
        round.winnerPool = roundFactionPools[roundId][winner];

        // 记录结算用的随机源信息
        round.settledBlockNumber = block.number - 1;
        round.settledBlockHash = bHash;

        emit RoundSettled(
            roundId,
            winner,
            round.totalPool,
            round.winnerPool,
            round.settledBlockNumber,
            round.settledBlockHash,
            roundFactionPools[roundId]
        );
    }

    // ------------------- Claiming Functions -------------------

    /**
     * @dev 内部领奖逻辑
     */
    function _processClaim(
        address user,
        uint256 roundId
    ) internal returns (uint256) {
        BetInfo storage bet = bets[roundId][user];
        if (bet.amount == 0) return 0; // 没玩
        if (bet.isClaimed) return 0; // 领过了

        RoundInfo storage round = rounds[roundId];
        if (!round.isSettled) return 0; // 没结算

        if (bet.faction != round.winningFaction) {
            // 输了
            return 0; // 没奖
            // 注意：如果输了，是否需要标记 isClaimed 以省 Gas?
            // 没必要，反正只要 isClaimed=false 且 faction!=winner 就拿不到钱。
        }

        if (round.winnerPool == 0) {
            // 特殊情况：赢家阵营没人投？逻辑上如果有 bet.amount > 0 且 bet.faction == winner，
            // 那么 winnerPool 至少等于 bet.amount。所以这里应该是安全的。
            return 0;
        }

        // 计算奖金: (用户下注 / 赢家总池) * 总奖池
        // 全精度计算
        uint256 grossReward = (bet.amount * round.totalPool) / round.winnerPool;

        // 扣除 5% 手续费
        uint256 reward = (grossReward * (10000 - FEE_BASIS_POINTS)) / 10000;

        bet.isClaimed = true;
        return reward;
    }

    /**
     * @dev 用户主动领奖 (支持元交易)。
     */
    function claimRewards(uint256[] calldata roundIds) external nonReentrant {
        address user = _msgSender();
        uint256 totalReward = 0;

        for (uint256 i = 0; i < roundIds.length; i++) {
            uint256 reward = _processClaim(user, roundIds[i]);
            if (reward > 0) {
                totalReward += reward;
                emit RewardsClaimed(roundIds[i], user, reward);
            }
        }

        if (totalReward > 0) {
            _transferReward(user, totalReward);
        }
    }

    /**
     * @dev 服务器/管理员分发奖励 (Push)。
     */
    function distributeRewards(
        address user,
        uint256[] calldata roundIds
    ) external nonReentrant {
        require(
            msg.sender == owner() ||
                msg.sender == operator ||
                isTrustedForwarder(msg.sender),
            "Unauthorized"
        );
        uint256 totalReward = 0;

        for (uint256 i = 0; i < roundIds.length; i++) {
            uint256 reward = _processClaim(user, roundIds[i]);
            if (reward > 0) {
                totalReward += reward;
                emit RewardsClaimed(roundIds[i], user, reward);
            }
        }

        if (totalReward > 0) {
            _transferReward(user, totalReward);
        }
    }

    function _transferReward(address to, uint256 amount) internal {
        if (paymentToken.balanceOf(address(this)) < amount)
            revert InsufficientContractBalance();
        bool success = paymentToken.transfer(to, amount);
        require(success, "Transfer failed");
    }

    // ------------------- Admin Functions -------------------

    function setMaxBetAmount(uint256 _amount) external onlyOwner {
        maxBetAmount = _amount;
        emit MaxBetAmountUpdated(_amount);
    }

    function setOperator(address _newOperator) external onlyOwner {
        require(_newOperator != address(0), "Invalid operator");
        emit OperatorUpdated(operator, _newOperator);
        operator = _newOperator;
    }

    /**
     * @dev 提取合约里的误转资金或输家沉淀资金 (如果项目方要抽水，也可在此实现)。
     * 注意：这里尚未实现“输家资金留存”的具体分配逻辑（如分红、销毁）。
     * 目前作为 Admin 提取。
     */
    function withdrawFunds(address token, uint256 amount) external onlyOwner {
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");
    }

    // ------------------- View Helpers -------------------

    /**
     * @dev 获取轮次完整状态，供 UI 使用。
     * @param _roundId 轮次ID。如果传入 0，则返回当前正在进行的轮次。
     */
    function getRoundState(
        uint256 _roundId
    )
        external
        view
        returns (
            uint256 roundId,
            uint256 totalPool,
            uint256[4] memory factionPools,
            bool isOpen,
            bool isSettled,
            uint8 winningFaction,
            uint256 winnerPool,
            uint256 settledBlockNumber,
            bytes32 settledBlockHash
        )
    {
        if (_roundId == 0) {
            roundId = getCurrentRoundId();
        } else {
            roundId = _roundId;
        }

        RoundInfo storage round = rounds[roundId];

        totalPool = round.totalPool;
        factionPools = roundFactionPools[roundId];
        isOpen =
            isBettingOpen(block.timestamp) &&
            (roundId == getCurrentRoundId());
        // 注意：只有当前最新的且在时间窗口内的才算 open。历史未结算的不能投，未来的也不能投。
        // 上面的 isOpen 逻辑：如果是查询历史 roundId，isBettingOpen(now) 可能是 true (如果刚好在分钟数内)，
        // 但 roundId != currentRoundId，所以这逻辑没问题。

        isSettled = round.isSettled;
        winningFaction = round.winningFaction;
        winnerPool = round.winnerPool;
        settledBlockNumber = round.settledBlockNumber;
        settledBlockHash = round.settledBlockHash;
    }
}
