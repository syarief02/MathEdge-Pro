
# MathEdge Pro EA for MT4

An MT4 Expert Advisor that implements the **MathEdge Pro** strategy using **New York (NY) session logic** and **daily math levels**.

This EA is **daily-data driven** (not timeframe dependent) and is intended for **indices** such as **US30** and **NAS100**.

---

## Table of Contents

- [What This EA Does](#what-this-ea-does)
- [Core Rules](#core-rules)
  - [Daily Data](#daily-data)
  - [Math](#math)
  - [Direction](#direction)
  - [Trade Sequence](#trade-sequence)
  - [Take Profit](#take-profit)
  - [Trading Window](#trading-window)
- [How It Executes on MT4](#how-it-executes-on-mt4)
- [Installation](#installation)
- [Inputs (Settings) Explained](#inputs-settings-explained)
- [Recommended Setup](#recommended-setup)
- [How To Verify Levels](#how-to-verify-levels)
- [Expiry](#expiry)
- [Build & Versioning](#build--versioning)
- [Limitations / Known Differences vs TradingView](#limitations--known-differences-vs-tradingview)
- [Roadmap](#roadmap)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## What This EA Does

At **18:00 New York time**, the EA locks a set of levels calculated from the **previous completed NY trading day** and then trades the current session using a strict 3-step execution sequence:

- **Trade 1:** at **PRV** (previous day close) → activates trading
- **Trade 2:** at **Low** (bullish) or **High** (bearish)
- **Trade 3:** at **CV** (daily close line used in the math)

All trades share **one unified take profit**.

---

## Core Rules

### Daily Data

At session start (18:00 NY), read and store:

- **O** = Daily Open (previous completed NY day)
- **H** = Daily High (previous completed NY day)
- **L** = Daily Low (previous completed NY day)
- **CV** = Daily Close (previous completed NY day)
- **PRV** = Previous Day Close (the close of the day before the CV day)

> The EA uses historical data. It does not recalculate intraday.

### Math

**Net Change**

NetChange = CV - PRV

### Direction

- If `NetChange > 0` → **BUY-only**
- If `NetChange < 0` → **SELL-only**
- If `NetChange = 0` → no trading (neutral day)

No opposite-direction trades are allowed.

### Trade Sequence

**Non-negotiable rule:**  
✅ No Trade 2 or Trade 3 unless **Trade 1 is triggered first**.

#### Bullish Day (BUY-only)
1. **T1:** Buy at **PRV** (activation)
2. **T2:** Buy at **L**
3. **T3:** Buy at **CV**

#### Bearish Day (SELL-only)
1. **T1:** Sell at **PRV** (activation)
2. **T2:** Sell at **H**
3. **T3:** Sell at **CV**

### Take Profit

Single unified TP for all trades:

TP = CV + NetChange

- If NetChange is negative, TP projects downward automatically.

### Trading Window

Timezone: **New York**

- Levels lock: **18:00 NY**
- Trading allowed: **18:00 NY → 15:29 NY (next day)**
- Outside this window: **no new trades**

---

## How It Executes on MT4

To match “price touch = execution” behavior, the EA places **pending orders**:

- T1 at PRV
- After T1 fills:
  - T2 at Low/High
  - T3 at CV
- All orders use the unified TP.

The EA can optionally:
- cancel pending orders outside the trading window
- close open trades at the window end (optional, not part of the core spec)

---

## Installation

1. Copy the EA file into:
   - `MQL4/Experts/`

2. Open **MetaEditor**:
   - Compile the `.mq4` file

3. In **MT4**:
   - Restart MT4 (or refresh Navigator)
   - Attach EA to the chart (US30 / NAS100)
   - Enable:
     - **AutoTrading ON**
     - **Allow Live Trading**
     - DLL imports not required

---

## Inputs (Settings) Explained

### Trade / Risk

- **MagicNumber**
  - Unique identifier for this EA’s trades.

- **Lots**
  - Fixed lot size per trade (when `UseRiskPercent = false`).

- **UseRiskPercent**
  - `false` = use fixed `Lots`
  - `true` = calculate lots using `RiskPercent` (approximate, depends on broker contract specs)

- **RiskPercent**
  - Used only when `UseRiskPercent = true`.

- **EmergencySL_Points**
  - Strategy spec does not define SL.
  - Default `0` (disabled).
  - Set >0 only if you want a hard safety SL (in points).

### Execution Filters

- **MaxSpreadPoints**
  - EA won’t place pending orders if spread exceeds this.

- **Slippage**
  - Slippage tolerance (points) when sending/modifying/closing orders.

### Symbol Controls

- **UseSymbolWhitelist**
  - Restrict EA to certain symbols.

- **AllowedSymbolsCSV**
  - Keywords matched against the chart symbol name.
  - Add your broker’s exact naming (example: `US30m`, `NAS100.cash`, etc).

### NY Session Times

- **NYDayStartHour / NYDayStartMinute**
  - Default 18:00 NY.

- **TradingEndHour / TradingEndMinute**
  - Default 15:29 NY.

### Daily OHLC Source (Important)

- **UseCustomNYDailyOHLC**
  - `true` = build NY-day OHLC using M1 bars (closer to TradingView NY boundaries)
  - `false` = use broker D1 candles (may differ from NY boundaries)

### Order Behaviour

- **PlacePendingOrders**
  - If true, EA places pending orders at PRV/L/H/CV.

- **CancelPendingsAfterWindow**
  - If true, EA removes pending orders outside trading window.

- **CloseOpenAtWindowEnd**
  - If true, EA closes any open positions after the window ends.
  - Optional; not required by the original strategy text.

### Visual

- **DrawLevels**
  - Draws PRV, CV, H, L, TP lines on chart.

- **ShowDashboard**
  - Shows real-time on-chart info panel with account, bias, levels, order status, and expiry countdown.

---

## Recommended Setup

For first live testing:
- Use **Demo first**
- `UseRiskPercent = false`
- `Lots = small` (example 0.01 / 0.02 depending broker)
- `EmergencySL_Points = 0` (match spec) or small safety SL if you must
- `DrawLevels = true` (verify calculations visually)
- `UseCustomNYDailyOHLC = true` first, then switch off if mismatch

---

## How To Verify Levels

1. Enable `DrawLevels = true`
2. Compare EA’s levels to your reference indicator:
   - PRV, CV, High, Low, TP
3. If they don’t match TradingView:
   - try `UseCustomNYDailyOHLC = false`
   - or adjust the NY-day builder based on broker server timezone

---

## Expiry

This repository version includes an expiry lock:

- Default expiry date (NY): **2026.03.28**
- 7-day warning alert before expiry
- After expiry:
  - EA stops placing new orders
  - pending orders are cancelled
  - optional: close open trades using `ExpiryCloseOpenTrades = true`

---

## Build & Versioning

- Platform: MT4 (MQL4)
- Recommended: compile with MetaEditor (MT4 build 600+)

Suggested version tags:
- `v1.0.0` initial stable release
- `v1.0.1` bugfixes / broker-time alignment improvements
- `v1.1.0` on-chart dashboard, improved logging, expiry countdown, OnDeinit cleanup, MathEdge Pro rebranding

---

## Limitations / Known Differences vs TradingView

- MT4 historical candles are based on **broker server time**
- TradingView logic may use strict **NY 18:00 session boundaries**
- The EA offers an NY OHLC builder using M1 bars, but perfect matching may require broker timezone alignment.

---

## Roadmap

- Add broker server timezone offset input for perfect NY OHLC building
- ~~Add detailed logs (print daily levels + state changes)~~ ✅ Done in v1.1
- Add "one order per level per day" hard lock (already mostly enforced)
- Add optional max orders / max exposure control
- ~~Add on-chart dashboard~~ ✅ Done in v1.1

---

## Disclaimer

This EA is provided for educational and testing purposes. Trading indices involves risk.  
Always test on a demo account first. You are responsible for all trading outcomes.

---

## License

- **Proprietary / All Rights Reserved** (restricted use)

