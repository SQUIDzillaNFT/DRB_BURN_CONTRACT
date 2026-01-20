# DRBSwapRouter

A simple, secure smart contract for ETH ↔ DRB swaps on Base network with automatic 0.25% burn and 0.25% creator fee.

## Features

- ✅ **Native ETH Support** - Buy DRB with ETH directly (no WETH needed)
- ✅ **Atomic Swaps** - All operations happen in one transaction
- ✅ **Automatic Fee Collection** - 0.25% burned, 0.25% sent to creator wallet
- ✅ **Slippage Protection** - Optional minimum output amounts
- ✅ **Gas Optimized** - Unlimited approvals set in constructor
- ✅ **Secure** - Reentrancy protection, safe token handling, access controls

## Contract Address

**Base Network:** `0x9f9F0D27b0471774232df0A15Fa39247E758322F`

[View on BaseScan](https://basescan.org/address/0x9f9F0D27b0471774232df0A15Fa39247E758322F)

## Contract Details

### Fees
- **Burn Fee:** 0.25% (sent to `0x000000000000000000000000000000000000dEaD`)
- **Creator Fee:** 0.25% (sent to creator wallet)
- **Total Contract Fee:** 0.5%
- **Uniswap Pool Fee:** 1%

### Functions

#### `buyDRB(uint256 minDRB)`
Buy DRB with ETH. Sends ETH with transaction, receives DRB after fees.

**Parameters:**
- `minDRB`: Minimum DRB to receive (after fees). Use `0` to accept any amount.

#### `sellDRB(uint256 drbAmount, uint256 minETH)`
Sell DRB for ETH. Requires DRB approval first.

**Parameters:**
- `drbAmount`: Amount of DRB to sell
- `minETH`: Minimum ETH to receive (after fees). Use `0` to accept any amount.

#### `checkPoolState()`
View function to check pool state and contract approvals (for debugging).

## Documentation

- **[Security Audit](./AUDIT_REPORT.md)** - Complete security analysis
- **[Frontend Guide](./FRONTEND_RESPONSIBILITIES.md)** - Integration guide for frontend developers

## Network Details

**Chain:** Base (Chain ID: 8453)

**Addresses:**
- **DRB Token:** `0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2`
- **WETH:** `0x4200000000000000000000000000000000000006`
- **Uniswap V3 Router:** `0x2626664c2603336E57B271c5C0b26F421741e481`
- **Uniswap V3 Factory:** `0x33128a8fC17869897dcE68Ed026d694621f6FDfD`
- **Pool (WETH/DRB 1%):** `0x5116773e18A9C7bB03EBB961b38678E45E238923`
- **Quoter V2:** `0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a`

## Usage

### For Users

**Buy DRB:**
1. Send ETH with `buyDRB(minDRB)` transaction
2. Receive DRB (after 0.5% fees)

**Sell DRB:**
1. Approve DRB token to contract address
2. Call `sellDRB(drbAmount, minETH)`
3. Receive ETH (after 0.5% fees)

### For Developers

See [FRONTEND_RESPONSIBILITIES.md](./FRONTEND_RESPONSIBILITIES.md) for complete integration guide.

## Security

This contract has been audited for security. See [AUDIT_REPORT.md](./AUDIT_REPORT.md) for details.

**Security Features:**
- ReentrancyGuard on all external functions
- SafeERC20 for all token transfers
- Access control (only owner can update creator wallet)
- Input validation
- Slippage protection

## License

MIT

## Disclaimer

This software is provided "as is" without warranty of any kind. Use at your own risk.
