// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeMath {
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) { unchecked { uint256 c = a + b; if (c < a) return (false, 0); return (true, c); } }
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) { unchecked { if (b > a) return (false, 0); return (true, a - b); } }
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) { unchecked { if (a == 0) return (true, 0); uint256 c = a * b; if (c / a != b) return (false, 0); return (true, c); } }
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) { unchecked { if (b == 0) return (false, 0); return (true, a / b); } }
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) { unchecked { if (b == 0) return (false, 0); return (true, a % b); } }
    function add(uint256 a, uint256 b) internal pure returns (uint256) { return a + b; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) { return a - b; }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) { return a * b; }
    function div(uint256 a, uint256 b) internal pure returns (uint256) { return a / b; }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) { return a % b; }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) { unchecked { require(b <= a, errorMessage); return a - b; } }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) { unchecked { require(b > 0, errorMessage); return a / b; } }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) { unchecked { require(b > 0, errorMessage); return a % b; } }
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETH(
        uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
    ) external returns (uint[] memory amounts);
    function addLiquidityETH(
        address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin,
        address to, uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

/// @title Ownable —— 手动实现，去除 OpenZeppelin 的 Context 依赖
abstract contract Ownable {
    address internal _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { require(owner() == msg.sender, "Ownable: caller is not owner"); _; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

contract ModaMintToken is IERC20, Ownable {
    using SafeMath for uint256;

    string private _name;
    string private _symbol;
    uint8  private constant _decimals = 18;
    uint256 private _totalSupply;
    uint256 private constant MAX_TAX = 2500;   // 最高 25%
    uint256 private constant DIVIDEND_PRECISION = 1e18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ===== 分红系统（修复版 Shareholder 模型）=====
    uint256 public dividendsPerShare;
    uint256 public totalDividendDistributed;
    uint256 public _availableDivFunds;
    uint256 public minHoldForDividend;
    uint256 public dividendBps;

    mapping(address => uint256) public totalExcluded;
    mapping(address => uint256) public totalRealised;
    mapping(address => bool) public isDividendExempt;

    // ===== 税费系统 =====
    uint256 public buyTaxBps;
    uint256 public sellTaxBps;
    uint256 public marketingBps;
    uint256 public burnBps;
    uint256 public liquidityBps;
    // ===== mint 加池比例（默认 7500 = 75%）=====
    uint256 public mintLiquidityBps = 7500;
    uint256 public pendingMarketingTokens;
    address public marketingWallet;
    address public dividendToken;    // 已弃用，分红现用原生 BNB

    // ===== DEX =====
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    bool public tradingActive;

    // ===== 反机器人（已移除）=====
    mapping(address => bool) public isExcludedFromTax;

    // ===== Mint 预售 =====
    uint256 public mintCostBNB;
    uint256 public tokensPerMint;      // 每份 mint 用户得到的代币数量
    uint256 public fillAmountBNB;
    uint256 public totalBNBCollected;
    mapping(address => uint256) public mintedAmount;
    mapping(address => uint256) public mintCount;       // 每钱包 mint 份数
    bool public presaleActive;
    bool public whitelistMintOnly;
    mapping(address => bool) public whitelist;
    uint256 public presaleTokenPct;                  // 预售代币占比（给用户部分）
    uint256 public lpTokenPct;                       // mint 加底池代币占比（另一块）

    // 预设两块独立额度，deploy 时计算好，mint 时独立扣除
    uint256 public totalPresaleTokens;   // = _totalSupply * presaleTokenPct / 100
    uint256 public totalLPTokens;        // = _totalSupply * lpTokenPct / 100
    uint256 public presaleTokensGiven;    // 已给用户代币数量
    uint256 public lpTokensUsed;         // 已用于 mint 加底池的代币数量

    // ===== 分红 swap 状态 =====
    uint256 public dividendSwapThreshold = 1 * 1e18;
    uint256 public pendingSwapForDividend;
    uint256 public pendingLiquidityTokens;
    bool private inSwap;
    modifier lockTheSwap() { inSwap = true; _; inSwap = false; }

    // ===== 流动性 BNB 独立核算 =====
    uint256 public pendingLiquidityBNB;

    // ===== 滑点保护（basis points，500 = 5%）=====
    uint256 public swapSlippage = 500;        // swap 滑点容忍度
    uint256 public liquiditySlippage = 500;    // 加池滑点容忍度

    // ===== 持币人迭代分红 =====
    address[] private _dividendHolders;
    mapping(address => uint256) private _holderIndex;
    mapping(address => bool) private _holderInList;
    uint256 public lastProcessedIndex;
    uint256 public dividendGasLimit = 400000;

    // ===== 事件 =====
    event TradingEnabled();
    event PresaleEnded();
    event DividendProcessed(uint256 tokensSwapped, uint256 dividendReceived);
    event DividendSwapFailed(uint256 amountAttempted);
    event DividendClaimed(address indexed holder, address indexed dividendToken, uint256 amount);
    event Mint(address indexed user, uint256 bnbCost, uint256 tokenAmount);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event MintLiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event LiquidityAddFailed(uint256 tokenAmount, uint256 bnbAmount);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        uint256 mintCostBNB_,
        uint256 fillBNB_,
        uint256 buyTax_,
        uint256 sellTax_,
        uint256 marketingPct_,
        uint256 burnPct_,
        uint256 dividendPct_,
        uint256 liquidityPct_,
        address marketingWallet_,
        address dividendToken_,
        uint256 minHoldForDividend_,
        uint256 presaleTokenPct_,
        uint256 lpTokenPct_,          // 新增：mint 加底池代币占比
        bool    whitelistMintOnly_,
        address owner_
    ) {
        require(buyTax_ <= MAX_TAX, "Buy tax too high");
        require(sellTax_ <= MAX_TAX, "Sell tax too high");
        require(marketingPct_ + burnPct_ + dividendPct_ + liquidityPct_ == 10000, "Tax alloc != 10000");
        require(fillBNB_ > 0, "Fill must > 0");
        require(mintCostBNB_ > 0, "Mint cost > 0");
        require(fillBNB_ >= mintCostBNB_, "Fill < mint cost");
        require(owner_ != address(0), "Owner zero");
        require(presaleTokenPct_ >= 1 && presaleTokenPct_ <= 99, "Presale pct 1-99");
        require(lpTokenPct_ >= 1 && lpTokenPct_ <= 99, "LP pct 1-99");
        require(presaleTokenPct_ + lpTokenPct_ <= 100, "presale+lp > 100");

        _name = name_;
        _symbol = symbol_;
        _totalSupply = totalSupply_ * 1e18;
        _balances[address(this)] = _totalSupply;

        emit OwnershipTransferred(address(0), msg.sender);
        emit OwnershipTransferred(msg.sender, owner_);
        _owner = owner_;

        dividendSwapThreshold = 1 * 1e18;
        dividendBps = dividendPct_;
        minHoldForDividend = minHoldForDividend_;
        dividendToken = dividendToken_;  // 保留兼容

        IUniswapV2Router02 _router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        uniswapV2Router = _router;
        uniswapV2Pair = IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH());

        isExcludedFromTax[address(this)] = true;
        isExcludedFromTax[owner_] = true;
        isExcludedFromTax[marketingWallet_] = true;
        isExcludedFromTax[address(_router)] = true;

        buyTaxBps = buyTax_;
        sellTaxBps = sellTax_;
        marketingBps = marketingPct_;
        burnBps = burnPct_;
        dividendBps = dividendPct_;
        liquidityBps = liquidityPct_;
        marketingWallet = marketingWallet_ != address(0) ? marketingWallet_ : msg.sender;
        whitelistMintOnly = whitelistMintOnly_;
        presaleTokenPct = presaleTokenPct_;
        lpTokenPct = lpTokenPct_;
        totalPresaleTokens = _totalSupply.mul(presaleTokenPct_).div(100);
        totalLPTokens = _totalSupply.mul(lpTokenPct_).div(100);
        // tokensPerMint = 每份 mint 用户得到的代币 = 总预售代币 × (mintCost / fill)
        tokensPerMint = totalPresaleTokens.mul(mintCostBNB_).div(fillBNB_);
        presaleActive = true;
        tradingActive = false;  // 预售期间不开放交易，但底池会逐步建立

        isDividendExempt[address(this)] = true;
        isDividendExempt[address(0)] = true;
        isDividendExempt[uniswapV2Pair] = true;

        mintCostBNB = mintCostBNB_;
        fillAmountBNB = fillBNB_;
        tokensPerMint = _totalSupply.mul(presaleTokenPct_).div(100).mul(mintCostBNB_).div(fillBNB_);
    }

    // ===== ERC20 =====
    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address a) public view override returns (uint256) { return _balances[a]; }
    function allowance(address a, address spender) public view override returns (uint256) { return _allowances[a][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: exceed allowance");
        unchecked { _approve(from, msg.sender, currentAllowance - amount); }
        _transfer(from, to, amount);
        return true;
    }

    function _approve(address _owner, address spender, uint256 amount) internal {
        require(_owner != address(0) && spender != address(0));
        _allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }

    receive() external payable {
        // 只接收 BNB（swap 回款、加池退回等），不再触发 mint
    }

    // ===== 核心 _transfer =====
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "Zero address");
        require(amount > 0, "Amount zero");
        require(_balances[from] >= amount, "Insufficient balance");

        if (!inSwap) {
            _tryAutoSwap();
        }

        if (dividendBps > 0) {
            _autoClaimDividend(from);
            _autoClaimDividend(to);
        }

        bool isDexTransfer = (from == uniswapV2Pair || to == uniswapV2Pair);
        if (isDexTransfer && !tradingActive) {
            require(isExcludedFromTax[from] || isExcludedFromTax[to], "Trading not active");
        }

        bool isBuy  = (from == uniswapV2Pair && to != address(uniswapV2Router));
        bool isSell = (to == uniswapV2Pair && from != address(uniswapV2Router));
        uint256 taxAmount = 0;

        if (!isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            if (isBuy)  taxAmount = amount.mul(buyTaxBps).div(10000);
            if (isSell) taxAmount = amount.mul(sellTaxBps).div(10000);
        }

        uint256 sendAmt = amount.sub(taxAmount);
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(sendAmt);

        if (taxAmount > 0) {
            _balances[address(this)] = _balances[address(this)].add(taxAmount);
            _distributeTax(taxAmount);
        }

        if (!isDividendExempt[from]) {
            totalExcluded[from] = cumulativeDividend(_balances[from]);
        }
        if (!isDividendExempt[to]) {
            totalExcluded[to] = cumulativeDividend(_balances[to]);
        }

        _updateHolderList(from);
        _updateHolderList(to);

        if (!inSwap) {
            _processDividendBatch();
        }

        emit Transfer(from, to, sendAmt);
    }

    function _distributeTax(uint256 taxAmt) internal {
        uint256 mkt = taxAmt.mul(marketingBps).div(10000);
        if (mkt > 0 && marketingWallet != address(0)) {
            pendingMarketingTokens = pendingMarketingTokens.add(mkt);
        }
        uint256 burn = taxAmt.mul(burnBps).div(10000);
        if (burn > 0) {
            _balances[address(this)] = _balances[address(this)].sub(burn);
            _totalSupply = _totalSupply.sub(burn);
            emit Transfer(address(this), address(0), burn);
        }
        uint256 liq = taxAmt.mul(liquidityBps).div(10000);
        if (liq > 0) {
            pendingLiquidityTokens = pendingLiquidityTokens.add(liq);
        }
        if (dividendBps > 0) {
            uint256 divAmt = taxAmt.mul(dividendBps).div(10000);
            if (divAmt > 0) {
                pendingSwapForDividend = pendingSwapForDividend.add(divAmt);
            }
        }
    }

    // ===== 分红系统 =====

    function _autoClaimDividend(address account) internal {
        if (isDividendExempt[account]) return;

        uint256 pending = getPendingDividend(account);
        if (pending == 0) return;
        if (_availableDivFunds < pending) return;

        totalRealised[account] += pending;

        totalExcluded[account] = cumulativeDividend(
            _balances[account]
        );

        _availableDivFunds = _availableDivFunds.sub(pending);

        (bool success, ) = payable(account).call{value: pending}("");
        if (success) {
            emit DividendClaimed(account, address(0), pending);
        }
    }

    function circulatingSupply() public view returns (uint256) {
        return _totalSupply
            - _balances[address(this)]
            - _balances[uniswapV2Pair]
            - _balances[address(0)];
    }

    function cumulativeDividend(uint256 share) internal view returns (uint256) {
        return share * dividendsPerShare / DIVIDEND_PRECISION;
    }

    function getPendingDividend(address account) public view returns (uint256) {
        if (isDividendExempt[account]) return 0;
        if (_balances[account] < minHoldForDividend) return 0;

        uint256 shareholderTotalDividends = cumulativeDividend(
            _balances[account]
        );

        uint256 shareholderTotalExcluded = totalExcluded[account];

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends - shareholderTotalExcluded;
    }

    function claimDividend() external {
        _autoClaimDividend(msg.sender);
    }

    function triggerDividendSwap() external {
        uint256 totalPending = pendingSwapForDividend + pendingLiquidityTokens + pendingMarketingTokens;
        require(totalPending >= dividendSwapThreshold, "Below threshold");
        require(!inSwap, "Swap in progress");
        _processDividendSwap();
    }

    function _tryAutoSwap() internal {
        if (inSwap || dividendSwapThreshold == 0) return;
        uint256 total = pendingSwapForDividend + pendingLiquidityTokens + pendingMarketingTokens;
        if (total >= dividendSwapThreshold) {
            _processDividendSwap();
        }
    }

    function _processDividendSwap() internal lockTheSwap {
        uint256 divAmt = pendingSwapForDividend;
        uint256 liqAmt = pendingLiquidityTokens;
        uint256 mktAmt = pendingMarketingTokens;
        uint256 totalAmt = divAmt + liqAmt + mktAmt;
        if (totalAmt == 0) return;

        pendingSwapForDividend = 0;
        pendingLiquidityTokens = 0;
        pendingMarketingTokens = 0;

        address weth = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), totalAmt);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        uint256 bnbBefore = address(this).balance;

        uint256 outMin = _getSwapOutMin(totalAmt);
        try uniswapV2Router.swapExactTokensForETH(
            totalAmt, outMin, path, address(this), block.timestamp
        ) {
            // swap 成功
        } catch {
            pendingSwapForDividend = pendingSwapForDividend.add(divAmt);
            pendingLiquidityTokens = pendingLiquidityTokens.add(liqAmt);
            pendingMarketingTokens = pendingMarketingTokens.add(mktAmt);
            emit DividendSwapFailed(totalAmt);
            return;
        }

        uint256 bnbReceived = address(this).balance - bnbBefore;

        uint256 mktBNB = (mktAmt > 0 && marketingWallet != address(0)) ? bnbReceived.mul(mktAmt).div(totalAmt) : 0;
        uint256 divBNB = (divAmt > 0) ? bnbReceived.mul(divAmt).div(totalAmt) : 0;
        uint256 liqBNB = bnbReceived.sub(mktBNB).sub(divBNB);

        if (mktBNB > 0) {
            (bool ok, ) = marketingWallet.call{value: mktBNB}("");
            if (!ok) {
                pendingMarketingTokens = pendingMarketingTokens.add(mktAmt);
            } else {
                emit DividendClaimed(marketingWallet, address(0), mktBNB);
            }
        }

        if (divBNB > 0) {
            uint256 supply = circulatingSupply();
            if (supply > 0) {
                dividendsPerShare += (divBNB * DIVIDEND_PRECISION / supply);
            }
            totalDividendDistributed += divBNB;
            _availableDivFunds += divBNB;
            emit DividendProcessed(totalAmt, divBNB);
        }

        if (liqBNB > 0) {
            pendingLiquidityBNB = pendingLiquidityBNB.add(liqBNB);
        }
    }

    // ===== 持币人注册表管理 =====
    function _updateHolderList(address account) internal {
        if (isDividendExempt[account]) return;
        uint256 bal = _balances[account];
        bool inList = _holderInList[account];

        if (bal >= minHoldForDividend && !inList) {
            _holderIndex[account] = _dividendHolders.length;
            _dividendHolders.push(account);
            _holderInList[account] = true;
        } else if (bal < minHoldForDividend && inList) {
            _removeHolder(account);
        }
    }

    function _removeHolder(address account) internal {
        if (!_holderInList[account]) return;
        uint256 idx = _holderIndex[account];
        uint256 lastIdx = _dividendHolders.length - 1;
        if (idx != lastIdx) {
            address lastHolder = _dividendHolders[lastIdx];
            _dividendHolders[idx] = lastHolder;
            _holderIndex[lastHolder] = idx;
        }
        _dividendHolders.pop();
        delete _holderIndex[account];
        delete _holderInList[account];
    }

    function _processDividendBatch() internal {
        uint256 count = _dividendHolders.length;
        if (count == 0) return;

        uint256 gasStart = gasleft();
        uint256 processed = 0;
        uint256 idx = lastProcessedIndex;
        uint256 maxGas = dividendGasLimit;

        while (processed < count && gasStart - gasleft() < maxGas) {
            if (idx >= count) idx = 0;
            address holder = _dividendHolders[idx];
            _autoClaimDividend(holder);
            idx++;
            processed++;
        }
        lastProcessedIndex = idx >= count ? 0 : idx;
    }

    function getDividendHolderCount() external view returns (uint256) {
        return _dividendHolders.length;
    }

    function getDividendHolders(uint256 start, uint256 count_) external view returns (address[] memory) {
        uint256 end = start + count_;
        if (end > _dividendHolders.length) end = _dividendHolders.length;
        if (start >= end) return new address[](0);
        address[] memory result = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = _dividendHolders[i];
        }
        return result;
    }

    function setDividendGasLimit(uint256 limit) external onlyOwner {
        dividendGasLimit = limit;
    }

    // ===== 内部辅助函数 =====

    /// @dev 根据 PancakeSwap pair 储备量计算 swap 最小输出（含滑点保护）
    function _getSwapOutMin(uint256 amountIn) internal view returns (uint256 minOut) {
        if (swapSlippage >= 10000) {
            return 0;
        }
        IUniswapV2Pair pair = IUniswapV2Pair(uniswapV2Pair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        uint256 reserveIn  = token0 == address(this) ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = token0 == address(this) ? uint256(reserve1) : uint256(reserve0);
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        // 恒定乘积公式（含 0.3% 手续费）
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator   = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        uint256 expectedOut = numerator / denominator;
        minOut = expectedOut * (10000 - swapSlippage) / 10000;
    }

    /// @dev 计算 addLiquidityETH 的 amountTokenMin / amountETHMin
    function _getLiquidityMins(uint256 tokenAmt, uint256 bnbAmt)
        internal
        view
        returns (uint256 minToken, uint256 minBnb)
    {
        if (liquiditySlippage >= 10000) {
            return (0, 0);
        }
        minToken = tokenAmt * (10000 - liquiditySlippage) / 10000;
        minBnb   = bnbAmt   * (10000 - liquiditySlippage) / 10000;
    }

    // ===== 管理员函数 =====
    function setBuyTax(uint256 bps) external onlyOwner { require(bps <= MAX_TAX); buyTaxBps = bps; }
    function setSellTax(uint256 bps) external onlyOwner { require(bps <= MAX_TAX); sellTaxBps = bps; }
    function setMarketingWallet(address w) external onlyOwner { require(w != address(0)); marketingWallet = w; }
    function excludeFromTax(address a, bool ex) external onlyOwner { isExcludedFromTax[a] = ex; }

    function withdrawBNB() external onlyOwner {
        uint256 totalBal = address(this).balance;
        uint256 protected = _availableDivFunds + pendingLiquidityBNB;
        uint256 withdrawable = totalBal > protected ? totalBal - protected : 0;
        require(withdrawable > 0, "No withdrawable BNB");
        (bool ok, ) = owner().call{value: withdrawable}("");
        require(ok, "BNB withdraw failed");
    }

    function emergencyWithdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    function setMarketingBps(uint256 bps) external onlyOwner {
        require(bps + burnBps + dividendBps + liquidityBps <= 10000, "Total > 100%");
        marketingBps = bps;
    }
    function setBurnBps(uint256 bps) external onlyOwner {
        require(marketingBps + bps + dividendBps + liquidityBps <= 10000, "Total > 100%");
        burnBps = bps;
    }
    function setDividendBps(uint256 bps) external onlyOwner {
        require(marketingBps + burnBps + bps + liquidityBps <= 10000, "Total > 100%");
        dividendBps = bps;
    }
    function setLiquidityBps(uint256 bps) external onlyOwner {
        require(marketingBps + burnBps + dividendBps + bps <= 10000, "Total > 100%");
        liquidityBps = bps;
    }

    function setMinHoldForDividend(uint256 amt) external onlyOwner { minHoldForDividend = amt; }
    function setDividendSwapThreshold(uint256 amt) external onlyOwner { dividendSwapThreshold = amt; }
    function setSwapSlippage(uint256 bps) external onlyOwner { require(bps <= 10000, "Max 10000"); swapSlippage = bps; }
    function setLiquiditySlippage(uint256 bps) external onlyOwner { require(bps <= 10000, "Max 10000"); liquiditySlippage = bps; }
    function setMintLiquidityBps(uint256 bps) external onlyOwner { require(bps >= 1000 && bps <= 10000, "Range 1000-10000"); mintLiquidityBps = bps; }
    function setLpTokenPct(uint256 bps) external onlyOwner {
        require(bps >= 1 && bps <= 99, "LP pct 1-99");
        require(presaleTokenPct + bps <= 100, "presale+lp > 100");
        require(presaleTokensGiven == 0 && lpTokensUsed == 0, "Cannot change after mint started");
        lpTokenPct = bps;
        totalLPTokens = _totalSupply.mul(bps).div(100);
    }
    function setPresaleTokenPct(uint256 bps) external onlyOwner {
        require(bps >= 1 && bps <= 99, "Presale pct 1-99");
        require(bps + lpTokenPct <= 100, "presale+lp > 100");
        require(presaleTokensGiven == 0 && lpTokensUsed == 0, "Cannot change after mint started");
        presaleTokenPct = bps;
        totalPresaleTokens = _totalSupply.mul(bps).div(100);
        tokensPerMint = totalPresaleTokens.mul(mintCostBNB).div(fillAmountBNB);
    }

    function completePresale() external onlyOwner {
        require(presaleActive, "Presale not active");
        presaleActive = false;
        emit PresaleEnded();
        _addFinalLiquidity();
    }

    function enableTrading() external onlyOwner {
        require(!tradingActive, "Already active");

        // 若预售仍在进行，先终止并注入仙液池（防止遗漏）
        if (presaleActive) {
            presaleActive = false;
            emit PresaleEnded();
            _addFinalLiquidity();
        }

        tradingActive = true;
        emit TradingEnabled();
    }

    // ===== Mint 预售 =====
    function setMintPrice(uint256 costBNB_, uint256 fillBNB_) external onlyOwner {
        require(costBNB_ > 0 && fillBNB_ >= costBNB_, "Invalid params");
        mintCostBNB = costBNB_;
        fillAmountBNB = fillBNB_;
        // 用乘法换掉双重除法，避免 fillBNB_/costBNB_ 整数截断
        tokensPerMint = totalPresaleTokens.mul(costBNB_).div(fillBNB_);
    }

    function addWhitelist(address[] calldata users) external onlyOwner {
        for (uint i = 0; i < users.length; i++) whitelist[users[i]] = true;
    }
    function removeWhitelist(address[] calldata users) external onlyOwner {
        for (uint i = 0; i < users.length; i++) whitelist[users[i]] = false;
    }
    function setWhitelistMintOnly(bool v) external onlyOwner { whitelistMintOnly = v; }

    /// @dev 新版 mint：每笔 mint 后自动将 mint 的 BNB + 等量代币加入流动性池
    function mint() public payable {
        require(presaleActive, "Presale not active");

        // --- 修复 Bug1：最后一笔 mint 因 fillAmountBNB 非 mintCostBNB 整数倍而永远失败 ---
        uint256 remaining = fillAmountBNB.sub(totalBNBCollected);
        require(remaining > 0, "Presale already full");
        bool isLast = remaining < mintCostBNB;

        if (isLast) {
            // 最后一笔：只允许发送恰好等于剩余量的 BNB
            require(msg.value == remaining, "Last mint: must send exact remaining BNB");
        } else {
            require(msg.value == mintCostBNB, "Invalid BNB amount");
        }

        if (whitelistMintOnly) require(whitelist[msg.sender], "Not whitelisted");

        // --- 修复：每钱包单次 mint 限制（可重置）---
        require(mintCount[msg.sender] == 0, "Already minted");
        mintCount[msg.sender] = 1;

        totalBNBCollected = totalBNBCollected.add(msg.value);

        // --- 计算代币数量：从预售额度里扣，最后一份用剩余量精确计算 ---
        uint256 tokenAmt;
        if (!isLast) {
            tokenAmt = tokensPerMint;
        } else {
            // 最后一份：把预售额度剩余的全部给用户
            tokenAmt = totalPresaleTokens.sub(presaleTokensGiven);
            require(tokenAmt > 0, "Token amount too small");
        }

        // 双重额度检查：预售额度 + LP额度
        require(presaleTokensGiven.add(tokenAmt) <= totalPresaleTokens, "Presale token pool exhausted");
        uint256 lpNeed = tokenAmt;
        if (lpTokensUsed.add(lpNeed) > totalLPTokens) {
            lpNeed = totalLPTokens.sub(lpTokensUsed);  // LP额度不够时，只用剩余部分
        }
        require(_balances[address(this)] >= tokenAmt.add(lpNeed), "Insufficient contract balance");

        // 发给 mint 用户
        _balances[msg.sender] = _balances[msg.sender].add(tokenAmt);
        _balances[address(this)] = _balances[address(this)].sub(tokenAmt);
        mintedAmount[msg.sender] = mintedAmount[msg.sender].add(tokenAmt);
        presaleTokensGiven = presaleTokensGiven.add(tokenAmt);

        emit Mint(msg.sender, msg.value, tokenAmt);
        emit Transfer(address(this), msg.sender, tokenAmt);

        totalExcluded[msg.sender] = cumulativeDividend(_balances[msg.sender]);
        _updateHolderList(msg.sender);

        // ===== 每笔 mint 自动加底池（用 LP 额度里的代币）=====
        _addMintLiquidity(lpNeed, msg.value);

        // 标记本钱包已 mint（已在上面标记过，此处删除重复）
        // mintCount[msg.sender] = 1;  // 已在第685行设置

        // 预售满时结束
        if (totalBNBCollected >= fillAmountBNB) {
            presaleActive = false;
            emit PresaleEnded();

            // 把合约剩余代币 + 合约剩余 BNB 全部加池
            _addFinalLiquidity();

            // 开启交易
            tradingActive = true;
            emit TradingEnabled();
        }
    }

    /// @dev 每笔 mint 后自动加底池：lpTokenAmt 代币 + bnbAmt BNB（只进部分底池）
    /// @param lpTokenAmt 从 LP 额度里出多少代币加底池
    function _addMintLiquidity(uint256 lpTokenAmt, uint256 bnbAmt) internal {
        if (lpTokenAmt == 0) return;
        if (_balances[address(this)] < lpTokenAmt) {
            emit LiquidityAddFailed(lpTokenAmt, bnbAmt);
            return;
        }

        // 只把 mintLiquidityBps 比例的 BNB 进底池，剩余留在合约
        uint256 lpBNB = bnbAmt.mul(mintLiquidityBps).div(10000);

        _balances[address(this)] = _balances[address(this)].sub(lpTokenAmt);
        _approve(address(this), address(uniswapV2Router), lpTokenAmt);

        (uint256 minToken, uint256 minBnb) = _getLiquidityMins(lpTokenAmt, lpBNB);
        try uniswapV2Router.addLiquidityETH{value: lpBNB}(
            address(this), lpTokenAmt, minToken, minBnb, owner(), block.timestamp
        ) {
            lpTokensUsed = lpTokensUsed.add(lpTokenAmt);
            emit MintLiquidityAdded(lpTokenAmt, lpBNB);
        } catch {
            _balances[address(this)] = _balances[address(this)].add(lpTokenAmt);
            emit LiquidityAddFailed(lpTokenAmt, lpBNB);
        }
    }

    /// @dev 预售满时：把合约剩余代币 + 合约剩余 BNB 全部加池
    function _addFinalLiquidity() internal {
        uint256 tokenBal = _balances[address(this)];
        uint256 bnbBal = address(this).balance;
        if (tokenBal == 0 || bnbBal == 0) return;

        // 扣除 pending 中的累积（补上 pendingMarketingTokens）
        uint256 pendingDiv = pendingSwapForDividend;
        uint256 pendingLiq = pendingLiquidityTokens;
        uint256 pendingMkt = pendingMarketingTokens;
        uint256 lockedTokens = pendingDiv + pendingLiq + pendingMkt;
        if (tokenBal <= lockedTokens) return;
        uint256 lpTokens = tokenBal - lockedTokens;

        pendingSwapForDividend = 0;
        pendingLiquidityTokens = 0;
        pendingMarketingTokens = 0;

        _approve(address(this), address(uniswapV2Router), lpTokens);

        (uint256 minToken, uint256 minBnb) = _getLiquidityMins(lpTokens, bnbBal);
        try uniswapV2Router.addLiquidityETH{value: bnbBal}(
            address(this), lpTokens, minToken, minBnb, owner(), block.timestamp
        ) returns (uint256 tokenUsed, uint256 bnbUsed, uint256) {
            emit LiquidityAdded(tokenUsed, bnbUsed);
        } catch {
            // 加池失败：恢复 pending 状态，BNB 和代币留在合约，不 revert 整笔交易
            pendingSwapForDividend = pendingSwapForDividend.add(pendingDiv);
            pendingLiquidityTokens = pendingLiquidityTokens.add(pendingLiq);
            pendingMarketingTokens = pendingMarketingTokens.add(pendingMkt);
            emit LiquidityAddFailed(lpTokens, bnbBal);
        }
    }

    function withdrawPresaleBNB() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "No BNB");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "BNB withdraw failed");
    }

    /// @dev 手动加池：只用 pendingLiquidityBNB
    function addLiquidity() external onlyOwner {
        uint256 tokenAmt = pendingLiquidityTokens;
        uint256 bnbAmt = pendingLiquidityBNB;
        require(tokenAmt > 0 && bnbAmt > 0, "Nothing to add");

        pendingLiquidityTokens = 0;
        pendingLiquidityBNB = 0;
        _approve(address(this), address(uniswapV2Router), tokenAmt);

        (uint256 minToken, uint256 minBnb) = _getLiquidityMins(tokenAmt, bnbAmt);
        uniswapV2Router.addLiquidityETH{value: bnbAmt}(
            address(this), tokenAmt, minToken, minBnb, owner(), block.timestamp
        );

        emit LiquidityAdded(tokenAmt, bnbAmt);
    }
}
