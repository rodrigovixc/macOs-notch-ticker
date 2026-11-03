<p align="center"><img src="Assets/AppIcon.png" width="160" alt="StockNotch icon"></p>

# StockNotch

A native macOS widget that lives in the MacBook notch and shows live stock and crypto prices, daily change and your portfolio's profit and loss. Hover the notch to expand it; move away and it tucks back in.

Built with SwiftUI and AppKit, no third-party dependencies.

## Features

- **Notch widget**: a black panel that blends with the notch, cycles through your assets (`PETR4 ▲ 1.20%`) and expands on hover into a full portfolio view. On displays without a notch it becomes a small pill centered on the menu bar.
- **Stocks and crypto**: Brazilian (B3) and US stocks via Yahoo Finance, crypto via the Binance public API. Prices refresh every 10 seconds.
- **Profit and loss**: record purchases and sales and see average cost, unrealized and realized P&L per asset and a single portfolio total (value, today's change, unrealized and realized return). Uses the average-cost method.
- **Language and currency**: Brazilian Portuguese or English, and totals in BRL, USD or EUR (**Settings** in the management window). Each asset's price stays in its own currency (PETR4 in R$, AAPL in US$); position value, P&L and totals are converted with Yahoo Finance exchange rates fetched in the same refresh as the prices.
- **Binance account sync (read-only)**: connect an API key and your spot and Simple Earn Flexible balances show up automatically. Enter your average purchase price per coin (in BRL) to include them in unrealized P&L.
- **Management window**: a native table with your assets, transaction history (purchases and sales) and the Binance connection.
- **Accessibility**: changes are shown with arrows and signs, not just color, and animations respect *Reduce Motion*.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16 or later (Swift 6)

## Build and run

```bash
git clone https://github.com/rodrigovixc/macOs-notch-ticker.git
cd macOs-notch-ticker
./build.sh
open StockNotch.app
```

`build.sh` compiles a release build, wraps it in an app bundle and signs it locally (ad-hoc). Drag the app to `/Applications` and add it under **System Settings → General → Login Items** to start it with your Mac.

To work on the code, open `Package.swift` in Xcode.

## Connecting Binance

1. On Binance, go to **Account → API Management** and create a key with **only "Enable Reading"** checked.
2. In the app, open the management window (the sliders icon in the notch) → **Binance**, and paste the API Key and Secret Key.

The app checks the key's permissions and refuses any key that can trade, transfer or withdraw. The secret is stored in the macOS Keychain, never in plain files.

## Data sources and limitations

| Market | Source | Delay |
|---|---|---|
| B3 (e.g. `PETR4`, `VALE3`) | Yahoo Finance (unofficial endpoint) | ~15 min (real-time B3 data is paid) |
| US stocks (e.g. `AAPL`) | Yahoo Finance (unofficial endpoint) | real time |
| Crypto (e.g. `BTC`, `ETH`) | Binance public API, BRL pairs (falls back to USDT × USDT/BRL) | real time |

- The Yahoo endpoint is unofficial and may change without notice.
- P&L uses the average-cost method, in date order. A purchase adds quantity and cost; a sale removes quantity and cost at the average price (which doesn't change) and adds `(sale price − average price) × quantity` to realized P&L. A position sold down to zero starts a new average on the next purchase. Only the day of each transaction is recorded, so on the same day purchases count before sales.
- A sale can't exceed what you held on that date, nor leave a later sale without enough quantity, and dates can't be in the future. A purchase that later sales depend on can only be deleted after those sales.
- Unrealized P&L is shown apart from realized P&L. It only counts what has a cost basis: your recorded purchases and Binance balances with an average price. Binance balances without one count toward total value and today's change only. Binance sales aren't imported, so there is no realized P&L for them.
- The default language and currency follow your system language (Portuguese → BRL, anything else → English and USD). Changing the language updates the app at once; system menus follow on the next launch.
- If an exchange rate is unavailable, the notch shows a warning instead of a wrong total. If Yahoo stops returning exchange rates, the last good rate is kept and the notch says since when it hasn't been updated (after 5 minutes).
- Converted figures use the current exchange rate. Today's change in another currency doesn't include that currency's own move during the day, and purchase costs are converted at today's rate, not the rate on the purchase date. So converted P&L and today's change can differ from Google Finance; figures in the asset's own currency match.
- In English, use a period for decimals when entering purchases (`32.50`); a comma is accepted only as a thousands separator (`1,234.50`).

## Where data is stored

- Portfolio: `~/Library/Application Support/StockNotch/carteira.json` (readable JSON, easy to back up): your assets with their purchases and sales, plus the Binance average prices. Files from earlier versions (a plain list of assets) are still read and are saved in the new format on the next change.
- Binance secret: macOS Keychain, service `io.github.rodrigovixc.stocknotch.binance`

## Tests

```bash
swift test
```

The tests cover average-cost P&L with sales (several purchases, partial sale, full sale and buyback, same-day purchase and sale), sale validation, reading the old `carteira.json` format, realized P&L in totals, currency conversion and the single converted total (including Binance balances and missing exchange rates), symbol normalization, decimal parsing in both languages (`1.234,56`, `0.5`, `1,234.56`), translations, currency formatting per language, settings defaults and persistence, and Binance request signing, checked against the example in the Binance documentation.

## Project structure

```
Sources/StockNotch/
├── App.swift       # app entry point, formatting helpers, shared UI pieces
├── Ajustes.swift   # language and currency settings, tr() translation helper
├── Notch.swift     # notch panel, hover tracking, collapsed/expanded views
├── Painel.swift    # management window: assets table, transactions, Binance, settings
├── Carteira.swift  # portfolio model, persistence, quotes, exchange rates, totals
├── Operacoes.swift # purchases and sales, average-cost position, sale validation
└── Binance.swift   # signed read-only API calls and Keychain storage
```
