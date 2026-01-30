# Samsara Intercepted Transactions

## Buy navSOL (SOL → navSOL)

**Intercepted**: 2026-01-18T10:29:25.923Z

### Transaction Summary

| Field | Value |
|-------|-------|
| Program | Mayflower (`AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v`) |
| Discriminator | `[30, 205, 124, 67, 20, 142, 236, 136]` |
| Data Length | 24 bytes |
| Account Count | 18 accounts |
| Lookup Table | `HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd` |

### Instruction Data Decoding

Raw data: `1ecd7c43148eec88809698000000000008ba020800000000`

| Offset | Bytes (hex) | Value | Interpretation |
|--------|-------------|-------|----------------|
| 0-7 | `1ecd7c43148eec88` | - | Discriminator |
| 8-15 | `8096980000000000` | 10,000,000 | Input: 0.01 SOL (lamports) |
| 16-23 | `08ba020800000000` | 134,429,192 | Min output (slippage protection?) |

### Transaction Flow

```
1. ComputeBudget: Set compute unit limit (309967 units)
2. ComputeBudget: Set compute unit price (327209 microLamports)
3. AssociatedToken: Create wSOL ATA for user (idempotent)
4. System: Transfer 0.01 SOL to wSOL ATA
5. Token: SyncNative (wrap SOL)
6. AssociatedToken: Create navSOL ATA for user (idempotent)
7. MAYFLOWER: Buy navSOL ← MAIN INSTRUCTION
8. Token: CloseAccount (unwrap remaining SOL)
```

### Address Lookup Table Contents

**Table Address**: `HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd`

| LUT Index | Address | Label |
|-----------|---------|-------|
| 0 | `A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc` | navSOL Mayflower Market |
| 1 | `Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC` | navSOL Market Group |
| 2 | `So11111111111111111111111111111111111111112` | Native SOL (wSOL mint) |
| 3 | `6AyryY5Eyt6fijg4LMwH8U9f9t41un13GFSDfot3VDVK` | (unknown) |
| 4 | `navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo` | navSOL Mint |
| 5 | `43vPhZeow3pgYa6zrPXASVQhdXTMfowyfNK87BYizhnL` | Market SOL Vault |
| 6 | `BCYzijbWwmqRnsTWjGhHbneST2emQY36WcRAkbkhsQMt` | Market navSOL Vault |
| 7 | `B8jccpiKZjapgfw1ay6EH3pPnxqTmimsm2KsTZ9LSmjf` | Fee Vault |
| 8 | `5hh9VjbkG3P2MqSiEtpUnCdboUwBrW4NKki5F6ntpyFC` | (unknown) |
| 9 | `DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj` | navSOL Market Metadata |
| 10 | `FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskTC` | Samsara Tenant |

**Transaction Combined Index Mapping**:
- Static accounts: 0-11
- LUT writable [4,0,5,6,7] → Combined indexes 12-16
- LUT readonly [2,1,9] → Combined indexes 17-19

### Mayflower Buy Instruction - Account Ordering (RESOLVED)

```
Idx | Combined | Address                                      | Role
----|----------|----------------------------------------------|---------------------------
0   | Static 0 | YOUR_WALLET_ADDRESS_HERE  | User Wallet (signer)
1   | Static 11| 81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z | Mayflower Tenant
2   | LUT 1    | Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC  | Market Group
3   | LUT 9    | DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj | Market Metadata
4   | LUT 0    | A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc | Mayflower Market
5   | Static 3 | GsCuiZUzBsUcwtm4E95QvNFRAE25u8TBvBAD1ZJycjGf | Price Oracle (Pyth?)
6   | Static 4 | 67x1iMn9Gx14TPUbifFft44TbC27atwsk22bKKS17im5 | Price Feed
7   | LUT 4    | navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo  | navSOL Mint
8   | LUT 2    | So11111111111111111111111111111111111111112  | wSOL Mint (input token)
9   | Static 2 | 68CDi2DE6fRVnTxJSSzB7aSWrYq3J8dSzAk7FrSigGFs | User navSOL ATA (output)
10  | Static 1 | FjU49HMCR5T9edwi2i6ngGyZkaG9XTXakrTSdkYFd9wo | User wSOL ATA (input)
11  | LUT 5    | 43vPhZeow3pgYa6zrPXASVQhdXTMfowyfNK87BYizhnL | Market SOL Vault
12  | LUT 6    | BCYzijbWwmqRnsTWjGhHbneST2emQY36WcRAkbkhsQMt | Market navSOL Vault
13  | LUT 7    | B8jccpiKZjapgfw1ay6EH3pPnxqTmimsm2KsTZ9LSmjf | Fee Vault
14  | Static 9 | TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA  | Token Program
15  | Static 9 | TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA  | Token Program (dup)
16  | Static 5 | EKVkmuwDKRKHw85NPTbKSKuS75EY4NLcxe1qzSPixLdy | Authority/Signer PDA
17  | Static 10| AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v | Mayflower Program
```

### Account Role Summary

| Role | Address | Notes |
|------|---------|-------|
| **User Wallet** | (dynamic) | Signer, payer |
| **Mayflower Tenant** | `81JEJdJSZba...` | Protocol config |
| **Market Group** | `Lmdgb4NE4T...` | Groups related markets |
| **Market Metadata** | `DotD4dZAyr...` | Market parameters |
| **Mayflower Market** | `A5M1nWfi6A...` | Main market account |
| **Price Oracle** | `GsCuiZUzBs...` | Pyth price feed account |
| **Price Feed** | `67x1iMn9Gx...` | SOL price data |
| **navSOL Mint** | `navSnrYJkC...` | Output token mint |
| **wSOL Mint** | `So1111...112` | Input token mint |
| **User navSOL ATA** | (dynamic) | User's navSOL account |
| **User wSOL ATA** | (dynamic) | User's wrapped SOL account |
| **Market SOL Vault** | `43vPhZeow3...` | Protocol's SOL reserves |
| **Market navSOL Vault** | `BCYzijbWwm...` | Protocol's navSOL reserves |
| **Fee Vault** | `B8jccpiKZj...` | Fee collection |
| **Authority PDA** | `EKVkmuwDKR...` | Market authority |
| **Mayflower Program** | `AVMmmRzwc2...` | CPI target |

### Key Observations

1. **Uses Mayflower program, not Samsara** - Buy operations go through Mayflower
2. **Address Lookup Table** - Uses ALT for efficiency (reduces transaction size)
3. **Wrapped SOL flow** - Creates temporary wSOL account, closes after
4. **18 accounts** - Complex instruction requiring many market accounts
5. **Slippage parameter** - Second u64 appears to be minimum output amount

### Discriminators Discovered

| Operation | Program | Discriminator | Hex |
|-----------|---------|---------------|-----|
| Buy navSOL | Mayflower | `[30, 205, 124, 67, 20, 142, 236, 136]` | `1ecd7c43148eec88` |

---

## Pending Interceptions

- [ ] Sell navSOL
- [ ] Stake navSOL
- [ ] Unstake navSOL
- [ ] Borrow against navSOL
- [ ] Repay borrow
- [ ] Claim rewards
