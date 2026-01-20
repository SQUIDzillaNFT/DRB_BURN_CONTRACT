// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
    function liquidity() external view returns (uint128);
}

/**
 * @title DRBSwapRouter - Simple Atomic Swap Contract
 * @notice Simple swap contract: ETH ↔ DRB with automatic 0.25% burn + 0.25% creator fee
 * @dev All swaps happen atomically in one transaction
 */
contract DRBSwapRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    address public constant DRB = 0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address public constant POOL = 0x5116773e18A9C7bB03EBB961b38678E45E238923;
    address public constant BURN = 0x000000000000000000000000000000000000dEaD;
    uint24 public constant FEE = 10000; // 1%

    address public creatorWallet;
    uint256 public constant BURN_RATE = 25; // 0.25%
    uint256 public constant CREATOR_RATE = 25; // 0.25%
    uint256 public constant DENOM = 10000;

    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 burned, uint256 creatorFee);
    event Burn(address indexed token, uint256 amount);
    event CreatorFee(address indexed token, uint256 amount);
    event CreatorWalletUpdated(address indexed oldWallet, address indexed newWallet);

    constructor() Ownable(0xAdEf887a75B32c7655692DB69A19108aFC1B91a7) {
        creatorWallet = 0x2d2eB3Ab43A5C33223376a20013D838a83d33155;
        
        // Pre-approve Uniswap Router for unlimited WETH and DRB
        // This avoids needing approval on every swap, saving gas
        IERC20(WETH).approve(ROUTER, type(uint256).max);
        IERC20(DRB).approve(ROUTER, type(uint256).max);
    }

    /**
     * @notice Update the creator wallet address (owner only)
     * @param _wallet New creator wallet address to receive fees
     */
    function setCreatorWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Cannot be zero address");
        require(_wallet != creatorWallet, "Must be different");
        address oldWallet = creatorWallet;
        creatorWallet = _wallet;
        emit CreatorWalletUpdated(oldWallet, _wallet);
    }

    /**
     * @notice Emergency function to set Uniswap Router approvals (owner only)
     * @dev This fixes approvals if they failed during deployment
     * @dev Sets unlimited approval for WETH and DRB to Uniswap Router
     */
    function contApprove() external onlyOwner {
        IERC20(WETH).approve(ROUTER, type(uint256).max);
        IERC20(DRB).approve(ROUTER, type(uint256).max);
    }

    /**
     * @notice Check pool state and contract approvals (for debugging)
     * @return poolExists Whether the pool exists
     * @return poolLiquidity Current active liquidity in the pool
     * @return wethApproval WETH approval to Router
     * @return drbApproval DRB approval to Router
     * @return contractWethBalance Contract's WETH balance
     */
    function checkPoolState() external view returns (
        bool poolExists,
        uint128 poolLiquidity,
        uint256 wethApproval,
        uint256 drbApproval,
        uint256 contractWethBalance
    ) {
        // Check if pool exists
        address poolAddress = IUniswapV3Factory(FACTORY).getPool(WETH, DRB, FEE);
        poolExists = (poolAddress != address(0) && poolAddress == POOL);
        
        // Get pool liquidity if pool exists
        if (poolExists) {
            poolLiquidity = IUniswapV3Pool(POOL).liquidity();
        }
        
        // Check approvals
        wethApproval = IERC20(WETH).allowance(address(this), ROUTER);
        drbApproval = IERC20(DRB).allowance(address(this), ROUTER);
        
        // Check contract WETH balance
        contractWethBalance = IERC20(WETH).balanceOf(address(this));
    }

    /**
     * @notice Buy DRB with ETH - Simple atomic swap
     * @param minDRB Minimum DRB tokens you want to receive (after fees)
     */
    function buyDRB(uint256 minDRB) external payable nonReentrant returns (uint256 drbReceived) {
        require(msg.value > 0, "Need ETH");
        
        // Wrap ETH to WETH first (contract needs WETH to swap)
        IWETH(WETH).deposit{value: msg.value}();
        
        // Verify contract has WETH after wrapping
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        require(wethBalance >= msg.value, "WETH wrap failed");
        
        // Calculate minimum DRB to ask Uniswap for (accounting for 0.5% fees we'll subtract)
        // If user wants minDRB after fees, we need to ask Uniswap for: minDRB / (1 - 0.005)
        // Formula: uniswapMin = minDRB * DENOM / (DENOM - totalFees)
        uint256 uniswapMin = 0;
        if (minDRB > 0) {
            uint256 totalFeeRate = BURN_RATE + CREATOR_RATE; // 50 (0.5%)
            uniswapMin = (minDRB * DENOM) / (DENOM - totalFeeRate);
        }
        
        // Verify approval is set (safety check)
        uint256 allowance = IERC20(WETH).allowance(address(this), ROUTER);
        require(allowance >= msg.value, "Insufficient WETH allowance");
        
        // Approval already set to unlimited in constructor - no need to approve again!
        // Swap WETH → DRB through Uniswap (let Uniswap handle everything - 1% pool fee)
        // Router will pull WETH from this contract using the approval
        uint256 drbAmount = ISwapRouter(ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: DRB,
                fee: FEE,
                recipient: address(this),
                amountIn: msg.value,
                amountOutMinimum: uniswapMin,
                sqrtPriceLimitX96: 0
            })
        );
        
        // Take 0.5% fees (0.25% burn + 0.25% creator)
        uint256 burnAmt = (drbAmount * BURN_RATE) / DENOM;
        uint256 creatorAmt = (drbAmount * CREATOR_RATE) / DENOM;
        drbReceived = drbAmount - burnAmt - creatorAmt;
        
        // Check final amount >= minDRB (only if minDRB > 0)
        if (minDRB > 0) {
            require(drbReceived >= minDRB, "Slippage");
        }
        
        // Send fees
        IERC20(DRB).safeTransfer(BURN, burnAmt);
        IERC20(DRB).safeTransfer(creatorWallet, creatorAmt);
        IERC20(DRB).safeTransfer(msg.sender, drbReceived);
        
        emit Burn(DRB, burnAmt);
        emit CreatorFee(DRB, creatorAmt);
        emit Swap(msg.sender, WETH, DRB, msg.value, drbReceived, burnAmt, creatorAmt);
        
        return drbReceived;
    }

    /**
     * @notice Sell DRB for ETH - Simple atomic swap
     * @param drbAmount Amount of DRB to sell
     * @param minETH Minimum ETH you want to receive (after fees)
     */
    function sellDRB(uint256 drbAmount, uint256 minETH) external nonReentrant returns (uint256 ethReceived) {
        require(drbAmount > 0, "Need DRB");
        
        // Transfer DRB from user
        IERC20(DRB).safeTransferFrom(msg.sender, address(this), drbAmount);
        
        // Calculate fees (0.5% total)
        uint256 burnAmt = (drbAmount * BURN_RATE) / DENOM;
        uint256 creatorAmt = (drbAmount * CREATOR_RATE) / DENOM;
        uint256 swapAmt = drbAmount - burnAmt - creatorAmt;
        
        // Send fees
        IERC20(DRB).safeTransfer(BURN, burnAmt);
        IERC20(DRB).safeTransfer(creatorWallet, creatorAmt);
        
        // Approval already set to unlimited in constructor - no need to approve again!
        // Swap DRB → WETH through Uniswap (let Uniswap handle everything - 1% pool fee)
        // Frontend should calculate minETH accounting for fees
        uint256 wethAmount = ISwapRouter(ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: DRB,
                tokenOut: WETH,
                fee: FEE,
                recipient: address(this),
                amountIn: swapAmt,
                amountOutMinimum: minETH, // Let frontend calculate this correctly
                sqrtPriceLimitX96: 0
            })
        );
        
        // Check final amount >= minETH (only if minETH > 0)
        if (minETH > 0) {
            require(wethAmount >= minETH, "Slippage");
        }
        
        // Unwrap WETH to ETH and send to user
        IWETH(WETH).withdraw(wethAmount);
        (bool success, ) = msg.sender.call{value: wethAmount}("");
        require(success, "ETH send failed");
        
        emit Burn(DRB, burnAmt);
        emit CreatorFee(DRB, creatorAmt);
        emit Swap(msg.sender, DRB, WETH, drbAmount, wethAmount, burnAmt, creatorAmt);
        
        return wethAmount;
    }

    receive() external payable {
        require(msg.sender == WETH, "Only WETH");
    }
}