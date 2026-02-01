# Samsara & Mayflower PDA Seed Reference

## Discovery Method

The PDA seeds were extracted from the Samsara web app's client-side JavaScript bundles.

### How to reproduce

1. Open `https://samsara.nirvana.finance/solana/markets/SOL/earn` in Chrome.
2. Open DevTools (F12) > Sources tab.
3. Look at the loaded JS chunks under `_next/static/chunks/`.
4. The critical bundle is the Anchor client/IDL chunk (~670KB), identifiable by
   containing `t.IDL={version:` and `MayflowerPda`/`SamsaraPda` class definitions.
   At time of writing this was chunk `1087-0b667a30c3c33454.js`.
5. The file is minified. Split on `;` to make it readable:
   ```bash
   curl -s "https://samsara.nirvana.finance/_next/static/chunks/1087-0b667a30c3c33454.js" \
     | tr ';' '\n' | grep -E '(MayflowerPda|SamsaraPda|findProgramAddress|n\.from\(")'
   ```
6. The same bundle embeds the full Anchor IDL as `t.IDL={version:"2026.1.12",name:"samsara",...}`.

### Why this works

The Samsara web app is a Next.js SPA. All transaction building happens client-side --
PDA derivation, instruction serialization, and account resolution are done in the
browser before the wallet signs. The Anchor IDL and SDK classes are bundled into the
webpack chunks served to the browser. Since the browser must have this code to build
transactions, it is always available for inspection regardless of whether the Rust
source is published.

### Key chunk identification

The earn page (`/solana/markets/SOL/earn`) loads additional chunks beyond the home
page. Compare the `<script>` tags between the two pages to find earn-specific bundles.
The IDL/SDK chunk is shared across pages but the earn page also loads Redux slices
that reference `depositPrana`, `withdrawPrana`, and `collectRevPrana` action types.

---

## Program IDs

| Program | Address |
|---------|---------|
| Samsara | `SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7` |
| Mayflower | `AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v` |

---

## Mayflower PDA Seeds

Derived against the **Mayflower program ID**.

| Method | Seed String | Parameters | Seeds |
|--------|------------|------------|-------|
| `logAccount()` | `"log"` | -- | `["log"]` |
| `tenant()` | `"tenant"` | seedAddress | `["tenant", seedAddress]` |
| `marketGroup()` | `"market_group"` | seedAddress | `["market_group", seedAddress]` |
| `market()` | `"market"` | seedAddress | `["market", seedAddress]` |
| `marketMeta()` | `"market_meta"` | seedAddress | `["market_meta", seedAddress]` |
| `marketLinear()` | `"market_linear"` | marketMetaAddress | `["market_linear", marketMetaAddress]` |
| `marketMulti()` | `"market_multi_curve"` | marketMetaAddress | `["market_multi_curve", marketMetaAddress]` |
| `mintOptions()` | `"mint_options"` | marketMetaAddress | `["mint_options", marketMetaAddress]` |
| `liqVaultMain()` | `"liq_vault_main"` | marketMetaAddress | `["liq_vault_main", marketMetaAddress]` |
| `revEscrowGroup()` | `"rev_escrow_group"` | marketMetaAddress | `["rev_escrow_group", marketMetaAddress]` |
| `revEscrowTenant()` | `"rev_escrow_tenant"` | marketMetaAddress | `["rev_escrow_tenant", marketMetaAddress]` |
| `personalPosition()` | `"personal_position"` | marketMetaAddress, owner | `["personal_position", marketMetaAddress, owner]` |
| `personalPositionEscrow()` | `"personal_position_escrow"` | personalPositionAddress | `["personal_position_escrow", personalPositionAddress]` |

### Chained derivations (Mayflower)

```
marketMeta ─────────────┬──> marketLinear
                        ├──> marketMulti
                        ├──> mintOptions
                        ├──> liqVaultMain
                        ├──> revEscrowGroup
                        └──> revEscrowTenant

marketMeta + owner ─────> personalPosition ──> personalPositionEscrow
```

---

## Samsara PDA Seeds

Derived against the **Samsara program ID**.

| Method | Seed String | Parameters | Seeds |
|--------|------------|------------|-------|
| `logCounter()` | `"log_counter"` | -- | `["log_counter"]` |
| `tenant()` | `"tenant"` | seedAddress | `["tenant", seedAddress]` |
| `market()` | `"market"` | marketMeta | `["market", marketMeta]` |
| `marketCashEscrow()` | `"cash_escrow"` | market | `["cash_escrow", market]` |
| `personalGovAccount()` | `"personal_gov_account"` | market, owner | `["personal_gov_account", market, owner]` |
| `personalGovPranaEscrow()` | `"prana_escrow"` | govAccount | `["prana_escrow", govAccount]` |

### Cross-program delegation

`SamsaraPda.personalAccount()` does NOT derive its own PDA. It delegates to
`MayflowerPda.personalPosition()` using the **Mayflower program ID**:

```
personalAccount({mayflowerMarketMetaAddress, owner, mayflowerProgramId})
  => MayflowerPda(mayflowerProgramId).personalPosition({marketMetaAddress, owner})
  => seeds: ["personal_position", marketMetaAddress, owner] with Mayflower program
```

Similarly, `SamsaraPda.personalZenEscrow()` uses seed `"zen_escrow"` with the
Samsara program:

```
personalZenEscrow({personalAccount})
  => seeds: ["zen_escrow", personalAccount] with Samsara program
```

### Chained derivations (Samsara)

```
market + owner ──> personalGovAccount ──> personalGovPranaEscrow
market ──────────> marketCashEscrow
(singleton) ─────> logCounter
```

---

## Account Discriminators

Anchor account discriminators are `sha256("account:<StructName>")[0..8]`.

| Account | Struct Name | Discriminator | Data Size |
|---------|------------|---------------|-----------|
| GovAccount | `GovAccount` | `[37, 169, 199, 114, 141, 109, 9, 167]` | 435 bytes |
| PersonalPosition | `PersonalPosition` | `[40, 172, 123, 89, 170, 15, 56, 141]` | ~121 bytes |
| MarketMeta | `MarketMeta` | `[95, 146, 205, 231, 152, 205, 151, 183]` | 488 bytes |
| Tenant (Mayflower) | `Tenant` | `[61, 43, 215, 51, 232, 242, 209, 170]` | -- |
| MarketGroup | `MarketGroup` | `[131, 205, 141, 87, 148, 210, 33, 36]` | -- |
| MarketLinear | `MarketLinear` | `[133, 114, 237, 100, 77, 96, 120, 49]` | 304 bytes |
| UserStagedRevenue | `UserStagedRevenue` | `[181, 47, 149, 167, 61, 95, 156, 69]` | -- |

---

## DepositPrana Instruction

**Program**: Samsara (`SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7`)

**Discriminator**: `sha256("global:deposit_prana")[0..8]` = `[167, 25, 30, 117, 67, 213, 8, 210]`

**Instruction data**: discriminator (8 bytes) + amount (u64 LE, 8 bytes) = 16 bytes total

**Accounts** (10 total):

| # | Name | Signer | Writable | Description |
|---|------|--------|----------|-------------|
| 0 | `depositor` | yes | yes | Wallet paying for the deposit (permissionless) |
| 1 | `tenant` | no | no | Samsara tenant |
| 2 | `market` | no | yes | Samsara market (per navToken) |
| 3 | `govAccount` | no | yes | PDA: `["personal_gov_account", market, owner]` |
| 4 | `mintPrana` | no | no | prANA mint (`CLr7G2af...`) |
| 5 | `pranaSrc` | no | yes | Depositor's prANA token account |
| 6 | `pranaEscrow` | no | yes | PDA: `["prana_escrow", govAccount]` (token account) |
| 7 | `tokenProgram` | no | no | SPL Token program |
| 8 | `samLogCounter` | no | yes | PDA: `["log_counter"]` (singleton) |
| 9 | `samsaraProgram` | no | no | Samsara program ID |

---

## WithdrawPrana Instruction

**Discriminator**: `sha256("global:withdraw_prana")[0..8]`

**Accounts** (10 total, same layout as depositPrana with minor naming differences):

| # | Name | Signer | Writable | Description |
|---|------|--------|----------|-------------|
| 0 | `owner` | yes | yes | Owner of the govAccount |
| 1 | `tenant` | no | no | Samsara tenant |
| 2 | `market` | no | yes | Samsara market |
| 3 | `govAccount` | no | yes | PDA: `["personal_gov_account", market, owner]` |
| 4 | `mintPrana` | no | no | prANA mint |
| 5 | `pranaDst` | no | yes | Destination prANA token account |
| 6 | `pranaEscrow` | no | yes | PDA: `["prana_escrow", govAccount]` |
| 7 | `tokenProgram` | no | no | SPL Token program |
| 8 | `samLogCounter` | no | yes | PDA: `["log_counter"]` |
| 9 | `samsaraProgram` | no | no | Samsara program ID |

---

## CollectRevPrana Instruction

**Accounts** (9 total):

| # | Name | Signer | Writable | Description |
|---|------|--------|----------|-------------|
| 0 | `owner` | yes | yes | Owner of the govAccount |
| 1 | `market` | no | yes | Samsara market |
| 2 | `govAccount` | no | yes | PDA: `["personal_gov_account", market, owner]` |
| 3 | `cashEscrow` | no | yes | PDA: `["cash_escrow", market]` |
| 4 | `cashDst` | no | yes | Destination token account for revenue |
| 5 | `mintMain` | no | no | Base token mint (e.g. wSOL) |
| 6 | `tokenProgram` | no | no | SPL Token program |
| 7 | `samLogCounter` | no | yes | PDA: `["log_counter"]` |
| 8 | `samsaraProgram` | no | no | Samsara program ID |

---

## Samsara IDL Instruction List

Version `2026.1.12`, program name `"samsara"`.

### Core operations
- `depositPrana` -- Deposit prANA to a market's govAccount
- `withdrawPrana` -- Withdraw prANA from a market's govAccount
- `collectRevPrana` -- Collect accumulated revenue from prANA deposits
- `initGovAccount` -- Initialize a user's govAccount for a market

### Governance
- `setVotesSimple` -- Set votes on a single ballot item
- `setVotes` -- Set votes on multiple ballot items
- `tallyVotes` -- Tally votes for a market

### Market operations
- `raiseFloorPreserveArea` -- Raise floor price preserving area
- `raiseFloorFromExcessLiquidity` -- Raise floor from excess liquidity
- `mintOptions` -- Mint options tokens
- `distributeRevFull` -- Distribute revenue for an epoch (renamed from `distributeRev`)

### Earn system
- `earnInitGlobalUserStagedRev` -- Init per-user-per-market revenue accumulator
- `earnInitUserShareTracker` -- Init per-user-per-market-per-epoch share tracker
- `earnAddPrana` -- Add prANA to earn system
- `earnRemovePrana` -- Remove prANA from earn system
- `earnCollectShares` -- Collect earned shares
- `finalizeEpoch` -- Finalize an epoch for revenue distribution

### Admin
- `adminSetPlatformRevShareMbps`
- `adminSetBurnerRevShareMbps`
- `adminSetTenantVoteChangeBufferSeconds`
- `adminCollectPlatformStagedRev`
- `adminSetAreaShrinkToleranceLamports`
- `adminSetMarketEarnParams`
- `adminSetMarketFlags`
- `adminSetMayflowerFlags`
- `adminSetFlagsExplicit`

### System
- `version`
- `initLogCounter`
- `initTenant`
- `initMarket`
- `initMarketScaled`
- `rootCloseAccount`
- `rootReallocAccount`
- `rootSetAccount`
- `rootTransferToken`
