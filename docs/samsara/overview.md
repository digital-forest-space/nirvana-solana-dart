# Samsara Reverse Engineering

## Overview

Samsara is Nirvana's second product - a decentralized derivatives platform built on Solana offering **navTokens**: synthetic assets engineered to provide amplified exposure to base assets with mathematically limited downside risk.

**Website**: https://samsara.nirvana.finance/

## Relationship to Nirvana

| Aspect | Nirvana (ANA) | Samsara |
|--------|---------------|---------|
| **Core Product** | Algorithmic token with rising floor | Derivatives (navTokens) |
| **Token Type** | ANA - appreciating floor token | navSOL, navZEC - amplified exposure tokens |
| **Governance Token** | prANA | prANA (shared!) |
| **Admin** | FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskTC | Same (Samsara Tenant) |
| **Revenue Sharing** | prANA holders | prANA holders (shared!) |

**Key Overlap**: Both protocols share the **prANA token** (`CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N`) for governance and revenue distribution.

## Program IDs

| Program | Address | Purpose |
|---------|---------|---------|
| **Samsara** | `SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7` | Main Samsara protocol |
| **Mayflower** | `AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v` | Market infrastructure |

## navTokens Mechanism

navTokens are derivatives with:
- **Amplified upside** potential relative to base asset
- **Mathematically limited downside** risk against base asset
- **Interest-free borrowing** against navTokens
- **Zero liquidation risk** on borrowed positions

### Active Markets

#### navSOL Market
| Account | Address |
|---------|---------|
| Base Token (SOL) | `So11111111111111111111111111111111111111112` |
| navSOL Mint | `navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo` |
| Samsara Market | `4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc` |
| Mayflower Market | `A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc` |
| Market Metadata | `DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj` |
| Market Group | `Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC` |
| Lookup Table | `HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd` |
| Market SOL Vault | `43vPhZeow3pgYa6zrPXASVQhdXTMfowyfNK87BYizhnL` |
| Market navSOL Vault | `BCYzijbWwmqRnsTWjGhHbneST2emQY36WcRAkbkhsQMt` |
| Fee Vault | `B8jccpiKZjapgfw1ay6EH3pPnxqTmimsm2KsTZ9LSmjf` |
| Authority PDA | `EKVkmuwDKRKHw85NPTbKSKuS75EY4NLcxe1qzSPixLdy` |

**Dutch Auction Config**: Initial boost 0.85, curvature 2.7, duration 7200s

#### navZEC Market
| Account | Address |
|---------|---------|
| Base Token (ZEC) | `A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS` |
| navZEC Mint | `navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe` |
| Samsara Market | `9JiASAyMBL9riFDPJtWCEtK4E2rr2Yfpqxoynxa3XemE` |
| Mayflower Market | `9SBSQvx5B8tKRgtYa3tyXeyvL3JMAZiA2JVXWzDnFKig` |
| Market Metadata | `HcGpdC8EtNpZPComvRaXDQtGHLpCFXMqfzRYeRSPCT5L` |

**Dutch Auction Config**: Initial boost 0.99, curvature 1, duration 7200s

## Fee Structure

| Fee Type | Value |
|----------|-------|
| Buy Fee | 10,000 µbps (0.1%) |
| Sell Fee | 10,000 µbps (0.1%) |
| Borrow Fee | 20,000 µbps (0.2%) |

## Tenant & Governance

| Account | Address |
|---------|---------|
| Mayflower Tenant | `81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z` |
| Samsara Tenant | `FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC` |
| Tenant Admin | `SiDxZaBNqVDCDxvVvXoGMLwLhzSbLVtaQing4RtPpDN` |
| prANA Token | `CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N` |

## Expected Operations

Based on the website functionality and Nirvana patterns:

### Read Operations
- [ ] Get navToken prices (floor, market price)
- [ ] Get user balances (navSOL, navZEC, base tokens)
- [ ] Get user position info (staked, borrowed)
- [ ] Get market statistics

### Write Operations
- [ ] Buy navTokens (SOL → navSOL, ZEC → navZEC)
- [ ] Sell navTokens (navSOL → SOL, navZEC → ZEC)
- [ ] Stake navTokens
- [ ] Unstake navTokens
- [ ] Borrow against staked navTokens
- [ ] Repay borrowed positions
- [ ] Claim rewards/revenue share

## PDA Derivation

### personal_position PDA

User-specific position account derived from Mayflower program:

```
Seeds: ["personal_position", market_metadata, user_pubkey]
Program: AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v (Mayflower)
```

### user_shares PDA (personalPositionEscrow)

Token account holding user's navToken shares, owned by personal_position.

The user_shares address is the `personalPositionEscrow` PDA:

```
Seeds: ["personal_position_escrow", personal_position]
Program: AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v (Mayflower)
```

This was verified on-chain: the derived `personalPositionEscrow` matches the
address stored in personal_position account data at bytes 72-103.

For new users, the buy script automatically prepends `init_personal_position`
to create both accounts in the same transaction.

### personal_position Account Structure

```
Offset 0-7:    Discriminator (8 bytes)
Offset 8-39:   Market Metadata pubkey (32 bytes)
Offset 40-71:  User pubkey (32 bytes)
Offset 72-103: User Shares pubkey (32 bytes)
Offset 104+:   Additional data (amounts, etc.)
```

## Instruction Discriminators

| Instruction | Discriminator (hex) | Purpose |
|-------------|---------------------|---------|
| init_personal_position | `28 ac 7b 59 aa 0f 38 8d` | Initialize user position (first use) |
| buy | `1e cd 7c 43 14 8e ec 88` | Buy navTokens (BuyWithExactCashInAndDeposit) |

## Implementation Status

### Completed
- [x] Buy navTokens (SOL → navSOL) - works for new and existing users
- [x] personal_position PDA derivation
- [x] user_shares PDA derivation (personalPositionEscrow)
- [x] New user support (auto init_personal_position before first buy)

### Pending
- [ ] Sell navTokens (navSOL → SOL)
- [ ] Stake navTokens
- [ ] Unstake navTokens
- [ ] Borrow against staked navTokens
- [ ] Repay borrowed positions
- [ ] Claim rewards/revenue share

## Technical Notes

- Uses **two programs** (Samsara + Mayflower) vs Nirvana's single program
- Dutch auction mechanism for price discovery
- Market-specific configurations (different for SOL vs ZEC)
- Lookup tables for transaction efficiency
- The buy instruction is actually "BuyWithExactCashInAndDeposit" which combines buying with auto-staking
