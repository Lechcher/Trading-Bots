---
trigger: always_on
---

# MQL5 Expert Advisor (EA) Development Rules

## 1. Project Architecture & File Roles
This project utilizes a three-file memory architecture. You must strictly adhere to the roles of each file before writing or modifying any MQL5 code:
* **`rules.md` (This File)**: The absolute guidelines for code generation, coding standards, and workflow.
* **`summary.md`**: The single source of truth for the EA's core trading logic. It contains the entry/exit conditions, required indicators, asset specifications, and strategy parameters. Always read this to understand *what* the EA does.
* **`memory.md`**: The long-term persistent storage for changelogs, debugging history, and ongoing issues. You must update this file whenever a change is made.

## 2. MQL5 Coding Standards & Best Practices
* **Strict Mode**: Always enforce strict compilation by ensuring `#property strict` is present (if applicable/legacy) and write clean, warning-free MQL5 code.
* **Standard Library**: Utilize the MQL5 Standard Library, particularly `#include <Trade\Trade.mqh>` (`CTrade`), for robust and standardized order execution.
* **Tick Efficiency**: Keep the `OnTick()` function lightweight. Offload complex calculations, indicator buffer loops, or signal generation to separate, well-named helper functions or classes.
* **Error Handling & Logging**: Never blindly execute trades. Always check the boolean return values of trade functions. If a trade fails, explicitly log the error using `Print("Error: ", GetLastError());` to facilitate debugging.
* **Memory & Resource Management**: Ensure all indicator handles created in `OnInit()` are properly released using `IndicatorRelease()` inside `OnDeinit()` to prevent memory leaks during backtesting or live deployment.

## 3. Risk Management & Order Execution
* **Explicit Risk Parameters**: Never assume default risk values. Always verify the risk settings (e.g., whether the user is utilizing a fixed lot size like `0.05`, or a dynamic risk percentage) explicitly against the rules defined in `summary.md`.
* **Pre-Trade Validation**: Before sending any order to the server, validate:
    * Sufficient free margin.
    * Valid Stop Loss (SL) and Take Profit (TP) levels relative to the current `SYMBOL_TRADE_STOPS_LEVEL`.
    * Correct volume step and minimum/maximum lot sizes for the symbol.
* **Symbol Independence**: Ensure the EA uses `_Symbol` or explicitly passed symbol parameters so it can run smoothly on multiple charts.

## 4. The "Long-Term Memory" Protocol
Whenever you modify the EA's code, fix a bug, or adjust a parameter based on user instructions, you MUST append a new entry to `memory.md`. Use the following format for consistency:

### Update Template for `memory.md`
**[YYYY-MM-DD] - [Brief Title of Change]**
* **Action**: Detail exactly what lines/functions were added, modified, or deleted in the `.mq5` file.
* **Reason**: Explain *why* the change was made (e.g., "Updated entry logic to match new requirement in summary.md", "Fixed Error 4756 during position open").
* **Status**: [Resolved / Needs Testing / Work in Progress]