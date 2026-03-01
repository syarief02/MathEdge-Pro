# MathEdge Pro

**Automated Math-Based Index Trading for MetaTrader 4**

MathEdge Pro is an Expert Advisor (EA) that trades US indices (**US30**, **NAS100**) using a rules-based mathematical strategy built on New York session data. It calculates daily levels, determines directional bias, and executes a strict 3-trade sequence — fully automated, no manual intervention required.

> **Platform:** MetaTrader 4 (MQL4)  
> **Instruments:** US30, NAS100 (and broker variants)  
> **Version:** 1.1  
> **Author:** Syarief Azman  
> **License:** MIT

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [How It Works](#how-it-works)
3. [Strategy Rules](#strategy-rules)
4. [Settings Reference](#settings-reference)
5. [On-Chart Dashboard](#on-chart-dashboard)
6. [Verifying Levels](#verifying-levels)
7. [License & Expiry](#license--expiry)
8. [Troubleshooting](#troubleshooting)
9. [Changelog](#changelog)
10. [Disclaimer](#disclaimer)

---

## Quick Start

### 1. Install

Copy `MathEdge Pro.mq4` into your MT4 data folder:

```
MQL4\Experts\
```

> **Tip:** In MT4, go to **File → Open Data Folder** to find the correct path.

### 2. Compile

Open the file in **MetaEditor** and click **Compile** (or press `F7`). Ensure **0 errors**.

### 3. Attach to Chart

1. Open a **US30** or **NAS100** chart (any timeframe — the EA is timeframe-independent).
2. Drag **MathEdge Pro** from the Navigator panel onto the chart.
3. In the EA properties dialog, go to the **Common** tab and enable:
   - ☑ **Allow live trading**
4. Configure inputs as needed (see [Settings Reference](#settings-reference)), then click **OK**.
5. Make sure the **AutoTrading** button on the toolbar is **ON** (green).

> **Important:** No DLL imports are required. Start on a **demo account** first.

---

## How It Works

Every day at **18:00 New York time**, MathEdge Pro:

1. **Locks daily levels** from the previous completed NY trading day (Open, High, Low, Close) and the day before that (Close).
2. **Calculates the net change** to determine directional bias (Buy-only or Sell-only).
3. **Places up to 3 pending orders** in sequence, all sharing a single unified take profit.

The EA uses pending orders to achieve "price touch = execution" behavior. No manual decisions are needed — the math defines everything.

### Trade Sequence at a Glance

```
Session Start (18:00 NY)
  │
  ├─ Calculate levels → PRV, CV, High, Low, TP
  ├─ Determine bias   → Net Change = CV − PRV
  │
  ├─ T1: Pending order at PRV (activation trade)
  │     ↓ (only after T1 fills)
  ├─ T2: Pending order at Low (buy) or High (sell)
  └─ T3: Pending order at CV
        │
        └─ All trades share TP = CV + Net Change
```

Trading window closes at **15:29 NY** the next day.

---

## Strategy Rules

### Daily Data

At session start (18:00 NY), the EA reads and stores the **previous completed NY day's** data:

| Symbol | Meaning |
|--------|---------|
| **O** | Daily Open |
| **H** | Daily High |
| **L** | Daily Low |
| **CV** | Closing Value (yesterday's close) |
| **PRV** | Previous Reference Value (day-before-yesterday's close) |

> These values are locked once per session. The EA does **not** recalculate intraday.

### Net Change & Bias

```
Net Change = CV − PRV
```

| Net Change | Bias | Action |
|------------|------|--------|
| **> 0** | Bullish | BUY orders only |
| **< 0** | Bearish | SELL orders only |
| **= 0** | Neutral | No trades today |

Opposite-direction trades are **never** allowed.

### Trade Execution

**Rule:** T2 and T3 are only placed **after T1 is filled** (activation confirmed).

#### Bullish Day

| Trade | Direction | Entry Level | Purpose |
|-------|-----------|-------------|---------|
| **T1** | Buy | PRV | Activation |
| **T2** | Buy | Low | Extreme entry |
| **T3** | Buy | CV | Closing value entry |

#### Bearish Day

| Trade | Direction | Entry Level | Purpose |
|-------|-----------|-------------|---------|
| **T1** | Sell | PRV | Activation |
| **T2** | Sell | High | Extreme entry |
| **T3** | Sell | CV | Closing value entry |

### Take Profit

All trades share a **single unified TP**:

```
TP = CV + Net Change
```

If Net Change is negative, the TP projects downward automatically.

### Trading Window

| Event | Time (New York) |
|-------|-----------------|
| Levels lock / session start | **18:00** |
| Trading window closes | **15:29** (next day) |
| Outside window | No new orders placed |

---

## Settings Reference

### Trade & Risk

| Input | Default | Description |
|-------|---------|-------------|
| `MagicNumber` | `260128` | Unique ID for this EA's orders. Change if running multiple instances. |
| `Lots` | `0.10` | Fixed lot size per trade. |
| `UseRiskPercent` | `false` | Set `true` to calculate lots dynamically based on `RiskPercent`. |
| `RiskPercent` | `1.0` | % of free margin risked per trade (only when `UseRiskPercent = true`). |
| `MaxSpreadPoints` | `300` | Orders are skipped if the current spread exceeds this value (in points). |
| `Slippage` | `5` | Maximum slippage tolerance (in points). |

### Symbol Whitelist

| Input | Default | Description |
|-------|---------|-------------|
| `UseSymbolWhitelist` | `true` | Restrict the EA to approved symbols only. |
| `AllowedSymbolsCSV` | `US30,NAS100,...` | Comma-separated list of symbol keywords. Add your broker's exact naming (e.g. `US30m`, `NAS100.cash`). |

### Session Timing

| Input | Default | Description |
|-------|---------|-------------|
| `NYDayStartHour` | `18` | NY session start hour. |
| `NYDayStartMinute` | `0` | NY session start minute. |
| `TradingEndHour` | `15` | NY trading window end hour. |
| `TradingEndMinute` | `29` | NY trading window end minute. |

### Daily OHLC Source

| Input | Default | Description |
|-------|---------|-------------|
| `UseCustomNYDailyOHLC` | `true` | `true` = build NY-day OHLC from M1 bars (closer to TradingView boundaries). `false` = use broker D1 candles. |

> **Recommendation:** Start with `true`. If levels don't match your reference, try `false`.

### Order Behavior

| Input | Default | Description |
|-------|---------|-------------|
| `PlacePendingOrders` | `true` | Place pending orders at calculated levels. |
| `CancelPendingsAfterWindow` | `true` | Automatically cancel unfilled pending orders after the window closes. |
| `CloseOpenAtWindowEnd` | `false` | Close any open positions when the window ends. (Optional — not part of core strategy.) |
| `EmergencySL_Points` | `0` | Hard stop-loss in points. `0` = disabled (strategy does not define SL). Set > 0 for safety. |

### Visual

| Input | Default | Description |
|-------|---------|-------------|
| `DrawLevels` | `true` | Draw horizontal lines for PRV, CV, H, L, TP on the chart. |
| `ShowDashboard` | `true` | Display a real-time info panel on the chart. |

---

## On-Chart Dashboard

When `ShowDashboard = true`, the EA displays a live panel on the chart showing:

- **Account info** — name, number, balance, equity
- **Symbol & spread** — current instrument and spread in points
- **Bias** — today's directional call (Bullish / Bearish / Flat)
- **Window status** — whether the trading window is Open or Closed
- **Levels** — PRV, CV, High, Low, TP, Net Change
- **Order status** — T1, T2, T3 placement status
- **Expiry countdown** — days remaining until license expiry

---

## Verifying Levels

To confirm the EA's calculations match your reference indicator:

1. Set `DrawLevels = true` — the EA draws colored lines on the chart:
   - 🟠 **PRV** (orange) — Previous Reference Value
   - 🔵 **CV** (cyan) — Closing Value
   - 🔴 **H** (red) — High
   - 🟢 **L** (green) — Low
   - 🟡 **TP** (yellow) — Take Profit
2. Compare these levels against TradingView or your reference source.
3. If levels don't match:
   - Try toggling `UseCustomNYDailyOHLC` between `true` and `false`
   - Your broker's D1 candle boundaries may differ from NY 18:00 boundaries

---

## License & Expiry

### Expiry

This version includes a license expiry mechanism:

- **Current expiry date:** `2026.03.28` (New York time)
- A **warning alert** is triggered **7 days** before expiry
- After expiry:
  - The EA stops placing new orders
  - All pending orders are cancelled
  - Open trades can optionally be closed (`ExpiryCloseOpenTrades = true`)

> Contact the provider for license renewal when you see the expiry warning.

### License

This software is released under the **MIT License**. See [LICENSE](LICENSE) for full terms.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| EA not trading | Check that **AutoTrading** is ON and the symbol matches the whitelist. |
| "Symbol not allowed" message | Add your broker's symbol name to `AllowedSymbolsCSV`. |
| Levels differ from TradingView | Toggle `UseCustomNYDailyOHLC`. Broker D1 candle boundaries may differ from NY 18:00. |
| Orders skipped (spread) | The current spread exceeds `MaxSpreadPoints`. Wait for lower spread or increase the limit. |
| EA expired | The license date has passed. Contact provider for renewal. |
| T2/T3 not appearing | T2 and T3 only place **after T1 is filled**. This is by design. |
| Dashboard not showing | Ensure `ShowDashboard = true` in the EA settings. |

---

## Changelog

### v1.1 — 2026-03-01

- Extended expiry to `2026-03-28`
- Added on-chart dashboard (account, bias, levels, order status, expiry countdown)
- Improved spread filter logging
- Added day-of-week filter (skip weekends/holidays)
- Improved comment clarity and code structure
- Rebranded to **MathEdge Pro**

### v1.0 — Initial Release

- MathEdge Pro strategy implementation
- Custom NY-day OHLC from M1 bars
- Three-tier pending order system (T1 / T2 / T3)
- DST-aware NY time conversion

---

## Disclaimer

This EA is provided for **educational and testing purposes only**. Trading indices involves significant risk of loss. Always test thoroughly on a **demo account** before using real funds. You are solely responsible for all trading outcomes.

---

*© 2026 Syarief Azman — MathEdge Pro*
