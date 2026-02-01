# Nirvana V2 PDA Seed Reference

## Discovery Method

The PDA seeds were extracted from the Nirvana web app's client-side JavaScript bundles.

### How to reproduce

1. Open `https://app.nirvana.finance/` in Chrome.
2. Open DevTools (F12) > Sources tab.
3. Look at the loaded JS chunks under `_next/static/chunks/`.
4. The critical bundle is the one containing `NvanaPda` class (~338KB).
   At time of writing this was chunk `7292-df3ba22c92fade75.js`.
5. The file is minified. Split on `;` to make it readable:
   ```bash
   curl -s "https://app.nirvana.finance/_next/static/chunks/7292-df3ba22c92fade75.js" \
     | tr ';' '\n' | grep -E '(NvanaPda|findProgramAddress|findAddress|r\.from\(")'
   ```
6. The same bundle also contains `NvanaIx` (instruction builder) and
   `PersonalAccountSdk` classes.

### Why this works

The Nirvana web app is a Next.js SPA. All transaction building happens client-side --
PDA derivation, instruction serialization, and account resolution are done in the
browser before the wallet signs. The SDK classes are bundled into the webpack chunks
served to the browser. Since the browser must have this code to build transactions,
it is always available for inspection.

### Key chunks

| Chunk | Size | Contents |
|-------|------|----------|
| `7292-df3ba22c92fade75.js` | ~338KB | `NvanaPda`, `NvanaIx`, `PersonalAccountSdk`, account structures |
| `6822-*.js` | ~20KB | Transaction builders (deposit/withdraw/borrow/claim instructions) |

---

## Program ID

| Program | Address |
|---------|---------|
| Nirvana V2 | `NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb` |

---

## NvanaPda Seeds

All PDAs are derived against the **Nirvana program ID**.

| Method | Seed String | Parameters | Seeds |
|--------|------------|------------|-------|
| `tenant()` | `"tenant"` | seedAddress | `["tenant", seedAddress]` |
| `personalAccount()` | `"personal_position"` | tenant, owner | `["personal_position", tenant, owner]` |
| `priceCurve()` | `"price_curve"` | tenant | `["price_curve", tenant]` |
| `curveBallot()` | `"curve_ballot"` | tenant | `["curve_ballot", tenant]` |
| `personalCurveBallot()` | `"personal_curve_ballot"` | tenant, owner | `["personal_curve_ballot", tenant, owner]` |
| `almsRewarder()` | `"alms_rewarder"` | tenant, owner | `["alms_rewarder", tenant, owner]` |
| `mettaRewarder()` | `"metta_rewarder"` | tenant, owner | `["metta_rewarder", tenant, owner]` |

### Important notes

- **Seed order for user-specific PDAs**: For methods that take both `owner` and `tenant`,
  the seed order is always `[seedString, tenant, owner]` -- tenant comes before owner.
- **`personalAccount` vs `personal_position`**: The JS method is named `personalAccount`
  but the actual seed string is `"personal_position"`. Our Dart class preserves both names
  for clarity.

### Chained derivations

```
seedAddress ──────────> tenant ──┬──> priceCurve
                                 ├──> curveBallot
                                 │
tenant + owner ──────────────────┼──> personalAccount (seed: "personal_position")
                                 ├──> personalCurveBallot
                                 ├──> almsRewarder
                                 └──> mettaRewarder
```

---

## Known Accounts (Mainnet)

| Account | Address | Source |
|---------|---------|--------|
| Program ID | `NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb` | config.dart |
| Tenant | `BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV` | config.dart |
| Price Curve | `Fx5u5BCTwpckbB6jBbs13nDsRabHb5bq2t2hBDszhSbd` | config.dart |
| ANA Mint | `5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW` | config.dart |
| NIRV Mint | `3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM` | config.dart |
| prANA Mint | `CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N` | config.dart |
| USDC Mint | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | config.dart |
| METTA Mint | `Aeg9L4a2dRX2PfUvcWeTAyYBfa7vAYXczfDrx1MSiTYS` | config.dart |

---

## Comparison with Current Implementation

The current `NirvanaAccountResolver.findPersonalAccount()` uses `getProgramAccounts`
RPC queries (data size 272, memcmp filter at offset 8) to find user accounts on-chain.
With the PDA seeds now known, this can be replaced with client-side `findProgramAddress`
derivation using `NirvanaPda.personalAccount(tenant, owner)`, eliminating the RPC call
and enabling first-time user account creation (same pattern as the Samsara/Mayflower
improvement).
