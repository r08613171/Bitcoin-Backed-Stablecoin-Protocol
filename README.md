# BitoCoin 💰⚡

> A Bitcoin-Backed Stablecoin Protocol on Stacks

## Overview 📋

BitoCoin is a decentralized protocol that enables users to mint a stablecoin by depositing Bitcoin (STX) as collateral. The protocol maintains price stability through over-collateralization and automated liquidation mechanisms.

## Features ✨

- **🔒 Collateralized Minting**: Deposit STX to mint BitoCoin tokens
- **💎 Over-collateralization**: 150% minimum collateral ratio
- **🚨 Liquidation Protection**: Automatic liquidation at 120% ratio
- **📊 Price Oracle**: Real-time BTC price updates
- **💸 Token Transfers**: Standard token functionality with approvals
- **⚡ Emergency Controls**: Admin shutdown capabilities

## Core Functions 🔧

### Collateral Management

```clarity
;; Deposit STX as collateral
(deposit-collateral amount)

;; Withdraw collateral (if safe)
(withdraw-collateral amount)
```

### Token Operations

```clarity
;; Mint stablecoins against collateral
(mint-tokens amount)

;; Burn tokens to reduce debt
(burn-tokens amount)

;; Transfer tokens
(transfer recipient amount)
```

### Liquidation

```clarity
;; Liquidate undercollateralized positions
(liquidate user)
```

## Usage Instructions 📖

### 1. Setup and Deployment

Deploy the contract using Clarinet:

```bash
clarinet deploy --testnet
```

### 2. Depositing Collateral

```bash
clarinet console
> (contract-call? .BitoCoin deposit-collateral u1000000)
```

### 3. Minting Tokens

After depositing collateral, mint tokens:

```bash
> (contract-call? .BitoCoin mint-tokens u500000)
```

### 4. Managing Position

Check your position status:

```bash
> (contract-call? .BitoCoin get-position tx-sender)
> (contract-call? .BitoCoin get-collateral-ratio tx-sender)
```

### 5. Repaying Debt

Burn tokens to reduce debt:

```bash
> (contract-call? .BitoCoin burn-tokens u100000)
```

## Protocol Parameters ⚙️

| Parameter | Value | Description |
|-----------|--------|-------------|
| **Collateral Ratio** | 150% | Minimum collateralization required |
| **Liquidation Ratio** | 120% | Threshold for liquidation |
| **Liquidation Penalty** | 110% | Reward for liquidators |
| **Oracle Update Interval** | 144 blocks | Minimum time between price updates |
| **Price Staleness** | 1440 blocks | Maximum age for price data |

## Security Features 🛡️

- **Oracle Price Validation**: Ensures price data freshness
- **Collateral Ratio Enforcement**: Prevents under-collateralized minting
- **Liquidation Mechanism**: Maintains protocol solvency
- **Access Controls**: Protected admin functions

## Error Codes 🚫

| Code | Error | Description |
|------|-------|-------------|
| 1000 | ERR_UNAUTHORIZED | Caller lacks permission |
| 1001 | ERR_INSUFFICIENT_COLLATERAL | Not enough collateral |
| 1002 | ERR_INVALID_AMOUNT | Invalid amount provided |
| 1003 | ERR_POSITION_NOT_FOUND | No position exists |
| 1004 | ERR_LIQUIDATION_THRESHOLD_NOT_MET | Position not liquidatable |
| 1005 | ERR_INSUFFICIENT_BALANCE | Insufficient token balance |
| 1006 | ERR_ORACLE_UPDATE_TOO_RECENT | Price updated too recently |
| 1007 | ERR_PRICE_TOO_OLD | Price data is stale |

## Development 👨‍💻

### Testing

Run the test suite:

```bash
clarinet test
```

### Local Development

Start local development environment:

```bash
clarinet integrate
```

## Contributing 🤝

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## License 📄

MIT License - see LICENSE file for details

---

**⚠️ Disclaimer**: This is experimental software. Use at your own risk in production environments.
