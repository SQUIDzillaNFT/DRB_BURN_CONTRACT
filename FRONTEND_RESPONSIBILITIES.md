# Frontend Responsibilities Guide

**Contract:** DRBSwapRouter  
**Network:** Base  
**Purpose:** Guide for frontend developers integrating with DRBSwapRouter

---

## Overview

The frontend is responsible for:
1. ✅ **Checking contract state** (paused status)
2. ✅ **Getting price quotes** from Uniswap
3. ✅ **Calculating slippage protection** (minDRB/minETH)
4. ✅ **Handling token approvals** (for selling DRB)
5. ✅ **Calling contract functions** with correct parameters
6. ✅ **Displaying fees and estimates** to users

The contract is responsible for:
- ✅ Executing swaps via Uniswap Router
- ✅ Collecting and distributing fees (0.25% burn + 0.25% creator)
- ✅ Enforcing slippage protection
- ✅ Wrapping/unwrapping ETH ↔ WETH

---

## Contract Addresses (Base Network)

```typescript
const CONTRACT_ADDRESS = "0x9f9F0D27b0471774232df0A15Fa39247E758322F"; // Your deployed contract
const DRB_TOKEN = "0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2";
const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
const UNISWAP_V3_QUOTER = "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a";
const UNISWAP_V3_ROUTER = "0x2626664c2603336E57B271c5C0b26F421741e481";
const POOL_FEE = 10000; // 1%
```

---

## 1. Buy DRB (ETH → DRB)

### Frontend Flow

**Step 1: Get Quote from Uniswap**
```typescript
// User wants to buy DRB with ETH
const ethAmount = parseEther("0.1"); // User enters 0.1 ETH

// Get quote from Uniswap Quoter
const quoteResult = await quoter.readContract({
  address: UNISWAP_V3_QUOTER,
  abi: QUOTER_ABI,
  functionName: 'quoteExactInputSingle',
  args: [{
    tokenIn: WETH_ADDRESS,
    tokenOut: DRB_TOKEN,
    amountIn: ethAmount,
    fee: POOL_FEE,
    sqrtPriceLimitX96: 0n,
  }],
});

const grossDRB = quoteResult[0]; // DRB from Uniswap (before contract fees)
```

**Step 2: Calculate Expected Output After Contract Fees**

```typescript
// Contract takes 0.5% total (0.25% burn + 0.25% creator)
// Formula: expectedDRB = grossDRB * 0.995
const CONTRACT_FEE_RATE = 0.995; // 99.5% = after 0.5% fee
const expectedDRB = (grossDRB * 995n) / 1000n;

console.log(`Expected DRB after 0.5% fee: ${formatEther(expectedDRB)} DRB`);
```

**Step 3: Apply Slippage Tolerance**

```typescript
// User's slippage preference (e.g., 2% = 200 basis points)
const slippageBps = 200; // 2% slippage tolerance

// Calculate minimum DRB user will accept
const minDRB = (expectedDRB * (10000n - BigInt(slippageBps))) / 10000n;

// Ensure minDRB is never zero (minimum 1 wei)
const minDRB = minDRB === 0n && expectedDRB > 0n ? 1n : minDRB;

console.log(`Min DRB (${slippageBps / 100}% slippage): ${formatEther(minDRB)} DRB`);
```

**Step 4: Call Contract**

```typescript
// No approval needed for buying (uses native ETH)
const tx = await writeContract({
  address: CONTRACT_ADDRESS,
  abi: CONTRACT_ABI,
  functionName: 'buyDRB',
  args: [minDRB],
  value: ethAmount, // Send ETH with transaction
});

await waitForTransactionReceipt(tx);
```

### Complete Example (Buy)

```typescript
async function buyDRB(ethAmount: bigint, slippageBps: number = 200) {
  // 1. Get quote
  const grossDRB = await getUniswapQuote(ethAmount, 'WETH', 'DRB');
  
  // 2. Calculate expected after fees
  const expectedDRB = (grossDRB * 995n) / 1000n;
  
  // 3. Apply slippage
  const minDRB = (expectedDRB * (10000n - BigInt(slippageBps))) / 10000n;
  
  // 4. Call contract
  return await writeContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'buyDRB',
    args: [minDRB],
    value: ethAmount,
  });
}
```

---

## 2. Sell DRB (DRB → ETH)

### Frontend Flow

**Step 1: Check and Approve DRB Token**

```typescript
// User wants to sell DRB
const drbAmount = parseEther("1000"); // User enters 1000 DRB

// Check current allowance
const currentAllowance = await readContract({
  address: DRB_TOKEN,
  abi: ERC20_ABI,
  functionName: 'allowance',
  args: [userAddress, CONTRACT_ADDRESS],
});

// Approve if needed
if (currentAllowance < drbAmount) {
  console.log('Approving DRB...');
  const approveTx = await writeContract({
    address: DRB_TOKEN,
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [CONTRACT_ADDRESS, drbAmount], // Or use MaxUint256 for unlimited
  });
  await waitForTransactionReceipt(approveTx);
  console.log('Approval confirmed');
}
```

**Step 2: Calculate Swap Amount (After Contract Fees)**

```typescript
// Contract takes 0.5% from drbAmount BEFORE swapping
// Formula: swapAmt = drbAmount * 0.995
const swapAmt = (drbAmount * 995n) / 1000n;

console.log(`Swap amount (after 0.5% fee): ${formatEther(swapAmt)} DRB`);
```

**Step 3: Get Quote from Uniswap**

```typescript
// Get quote for the swap amount (after fees)
const quoteResult = await quoter.readContract({
  address: UNISWAP_V3_QUOTER,
  abi: QUOTER_ABI,
  functionName: 'quoteExactInputSingle',
  args: [{
    tokenIn: DRB_TOKEN,
    tokenOut: WETH_ADDRESS,
    amountIn: swapAmt, // Use swapAmt, not drbAmount!
    fee: POOL_FEE,
    sqrtPriceLimitX96: 0n,
  }],
});

const expectedWETH = quoteResult[0]; // WETH from Uniswap
const expectedETH = expectedWETH; // Same value, WETH = ETH

console.log(`Expected ETH: ${formatEther(expectedETH)} ETH`);
```

**Step 4: Apply Slippage Tolerance**

```typescript
// User's slippage preference (e.g., 2%)
const slippageBps = 200; // 2% slippage tolerance

// Calculate minimum ETH user will accept
let minETH = (expectedETH * (10000n - BigInt(slippageBps))) / 10000n;

// Ensure minETH is never zero (minimum 1 wei)
if (minETH === 0n && expectedETH > 0n) {
  minETH = 1n;
}

console.log(`Min ETH (${slippageBps / 100}% slippage): ${formatEther(minETH)} ETH`);
```

**Step 5: Call Contract**

```typescript
const tx = await writeContract({
  address: CONTRACT_ADDRESS,
  abi: CONTRACT_ABI,
  functionName: 'sellDRB',
  args: [drbAmount, minETH], // drbAmount (full), minETH (after slippage)
});

await waitForTransactionReceipt(tx);
```

### Complete Example (Sell)

```typescript
async function sellDRB(drbAmount: bigint, slippageBps: number = 200) {
  // 1. Check/Approve DRB
  await ensureDRBApproval(drbAmount);
  
  // 2. Calculate swap amount after fees
  const swapAmt = (drbAmount * 995n) / 1000n;
  
  // 3. Get quote
  const expectedETH = await getUniswapQuote(swapAmt, 'DRB', 'WETH');
  
  // 4. Apply slippage
  const minETH = (expectedETH * (10000n - BigInt(slippageBps))) / 10000n;
  
  // 5. Call contract
  return await writeContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'sellDRB',
    args: [drbAmount, minETH],
  });
}

async function ensureDRBApproval(amount: bigint) {
  const allowance = await readContract({
    address: DRB_TOKEN,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [userAddress, CONTRACT_ADDRESS],
  });
  
  if (allowance < amount) {
    await writeContract({
      address: DRB_TOKEN,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [CONTRACT_ADDRESS, MaxUint256], // Unlimited approval
    });
  }
}
```

---

## Contract ABI (Required Functions)

```typescript
const CONTRACT_ABI = [
  {
    inputs: [{ name: 'minDRB', type: 'uint256' }],
    name: 'buyDRB',
    outputs: [{ name: 'drbReceived', type: 'uint256' }],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'drbAmount', type: 'uint256' },
      { name: 'minETH', type: 'uint256' }
    ],
    name: 'sellDRB',
    outputs: [{ name: 'ethReceived', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'checkPoolState',
    outputs: [
      { name: 'poolExists', type: 'bool' },
      { name: 'poolLiquidity', type: 'uint128' },
      { name: 'wethApproval', type: 'uint256' },
      { name: 'drbApproval', type: 'uint256' },
      { name: 'contractWethBalance', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'paused',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'checkUserApproval',
    outputs: [
      { name: 'allowance', type: 'uint256' },
      { name: 'userBalance', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'drbAmount', type: 'uint256' }],
    name: 'estimateSellFees',
    outputs: [
      { name: 'burnAmount', type: 'uint256' },
      { name: 'creatorAmount', type: 'uint256' },
      { name: 'swapAmount', type: 'uint256' },
      { name: 'totalFeeAmount', type: 'uint256' },
    ],
    stateMutability: 'pure',
    type: 'function',
  },
  {
    inputs: [{ name: 'estimatedDRB', type: 'uint256' }],
    name: 'estimateBuyFees',
    outputs: [
      { name: 'burnAmount', type: 'uint256' },
      { name: 'creatorAmount', type: 'uint256' },
      { name: 'netDRB', type: 'uint256' },
      { name: 'totalFeeAmount', type: 'uint256' },
    ],
    stateMutability: 'pure',
    type: 'function',
  },
] as const;
```

---

## Fee Structure

### Contract Fees
- **Burn Fee:** 0.25% (sent to burn address `0x000000000000000000000000000000000000dEaD`)
- **Creator Fee:** 0.25% (sent to creator wallet)
- **Total Contract Fee:** 0.5%

### Uniswap Pool Fee
- **Pool Fee:** 1% (handled by Uniswap V3 Router)

### Total Fees Per Swap
- **Buy:** ~1.5% total (0.5% contract + 1% Uniswap)
- **Sell:** ~1.5% total (0.5% contract + 1% Uniswap)

---

## Important Notes

### ⚠️ Critical for Buy Flow

1. **Quote uses WETH, not ETH:**
   - When getting quote, use `WETH_ADDRESS` as `tokenIn`
   - Contract wraps ETH to WETH internally

2. **Contract adjusts slippage:**
   - Contract calculates `uniswapMin` internally for Uniswap
   - Frontend passes `minDRB` (what user expects after all fees)

3. **No approval needed:**
   - Buying uses native ETH, no token approval required

### ⚠️ Critical for Sell Flow

1. **Approval is required:**
   - Users MUST approve DRB to contract before selling
   - Check allowance first, approve if needed

2. **Quote uses swapAmt, not drbAmount:**
   - Get quote for `swapAmt = drbAmount * 0.995` (after contract fees)
   - Contract already deducted fees before swapping

3. **minETH calculation:**
   - Calculate `minETH` from expected WETH output
   - Frontend must account for slippage only (contract fees already accounted in quote)

---

## Contract State Checks

### Check if Contract is Paused

**Always check if contract is paused before allowing swaps:**

```typescript
// Check pause status before any swap
const isPaused = await readContract({
  address: CONTRACT_ADDRESS,
  abi: CONTRACT_ABI,
  functionName: 'paused',
});

if (isPaused) {
  // Show message to user
  alert('Swaps are currently paused. Please try again later.');
  return;
}
```

**Recommended:** Check pause status when component mounts and disable swap buttons if paused.

---

## Diagnostic Functions

### Check User's DRB Approval

**Use this to check user's approval status before selling:**

```typescript
async function checkUserApprovalStatus(userAddress: string) {
  const result = await readContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'checkUserApproval',
    args: [userAddress],
  });
  
  const [allowance, userBalance] = result;
  
  return {
    allowance: allowance,
    userBalance: userBalance,
    needsApproval: allowance === 0n,
  };
}
```

**Use Case:** Display approval status in UI, show warning if no approval set.

### Estimate Fees

**Use these functions to show fee breakdown to users:**

```typescript
// For buy flow: Estimate fees based on Uniswap quote
async function estimateBuyFees(grossDRB: bigint) {
  const [burnAmount, creatorAmount, netDRB, totalFeeAmount] = await readContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'estimateBuyFees',
    args: [grossDRB], // Pass the DRB amount from Uniswap quote
  });
  
  return {
    burnAmount,
    creatorAmount,
    netDRB, // What user will actually receive
    totalFeeAmount,
  };
}

// For sell flow: Estimate fees based on user input
async function estimateSellFees(drbAmount: bigint) {
  const [burnAmount, creatorAmount, swapAmount, totalFeeAmount] = await readContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'estimateSellFees',
    args: [drbAmount], // Pass the full DRB amount user wants to sell
  });
  
  return {
    burnAmount,
    creatorAmount,
    swapAmount, // Amount that will be swapped (after fees)
    totalFeeAmount,
  };
}
```

**Use Case:** Display fee breakdown in UI:
- "0.25% burned (X DRB)"
- "0.25% creator fee (Y DRB)"
- "You'll receive Z DRB/ETH after fees"

---

## Error Handling

### Common Errors

**"Insufficient allowance" (Sell)**
- **Cause:** User hasn't approved DRB to contract
- **Fix:** Prompt user to approve DRB token

**"Slippage: received less than minimum"**
- **Cause:** Price moved unfavorably during transaction
- **Fix:** Retry with higher slippage tolerance or smaller amount

**"Need ETH" / "Need DRB"**
- **Cause:** User entered 0 amount
- **Fix:** Validate input before calling contract

**"Paused"**
- **Cause:** Contract is paused by owner
- **Fix:** Show message to user, disable swap buttons until unpaused

**"execution reverted"**
- **Cause:** Various (check transaction on BaseScan)
- **Fix:** Check transaction receipt for specific error

---

## User Experience Recommendations

1. **Check Contract State:**
   - Check `paused` status on component mount
   - Disable swap buttons if paused
   - Show clear message if contract is paused

2. **Show Fee Breakdown:**
   - Use `estimateBuyFees()` or `estimateSellFees()` to get exact fee amounts
   - Display 0.25% burn + 0.25% creator fee clearly
   - Show expected output after fees

3. **Slippage Settings:**
   - Default: 2% (200 basis points)
   - Allow users to adjust (0.1% - 5% recommended)
   - Warn if slippage is too high or too low

4. **Approval Flow:**
   - Use `checkUserApproval()` to check allowance before sell
   - Show approval status in UI
   - Show approval transaction separately
   - Consider unlimited approval (MaxUint256) for better UX

5. **Loading States:**
   - Show "Getting quote..." while fetching
   - Show "Checking approval..." while checking
   - Show "Approving..." during approval
   - Show "Swapping..." during swap transaction

6. **Success Feedback:**
   - Display transaction hash
   - Show amount received
   - Show fees burned/collected

---

## Testing Checklist

- [ ] Contract pause check works (disable buttons when paused)
- [ ] Buy flow works with small amounts (0.001 ETH)
- [ ] Buy flow works with large amounts (1+ ETH)
- [ ] Sell flow checks allowance correctly (using checkUserApproval)
- [ ] Sell flow approves and swaps correctly
- [ ] Fee estimation functions work (estimateBuyFees, estimateSellFees)
- [ ] Fee breakdown displays correctly
- [ ] Slippage protection works (try with 0% vs 2%)
- [ ] Error messages are user-friendly
- [ ] Quotes update when amount changes
- [ ] Quotes handle network errors gracefully
- [ ] Gas estimation works correctly

---

## Example UI Flow

```
Buy DRB:
1. Frontend checks: Contract paused? (if yes, disable button)
2. User enters: "0.1 ETH"
3. Frontend shows: "You'll receive ~X DRB (after 0.5% fees)"
4. User clicks "Buy"
5. Frontend: Get quote → Calculate minDRB → Call buyDRB()
6. Transaction confirms → Show success

Sell DRB:
1. Frontend checks: Contract paused? (if yes, disable button)
2. User enters: "1000 DRB"
3. Frontend shows: "You'll receive ~X ETH (after 0.5% fees)"
4. User clicks "Sell"
5. Frontend: Check approval (checkUserApproval) → Approve if needed → Get quote → Calculate minETH → Call sellDRB()
6. Transaction confirms → Show success
```

---

## Additional Resources

- **Uniswap V3 Quoter:** https://docs.uniswap.org/contracts/v3/reference/periphery/lens/QuoterV2
- **Base Network:** https://docs.base.org/
- **Contract Address:** `0x9f9F0D27b0471774232df0A15Fa39247E758322F`
- **BaseScan:** https://basescan.org/address/0x9f9F0D27b0471774232df0A15Fa39247E758322F

---

**Last Updated:** Current  
**Contract Version:** Final Production  
**New Features:** Emergency pause, diagnostic functions (checkUserApproval, estimateFees)
