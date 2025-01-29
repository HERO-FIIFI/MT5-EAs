//+------------------------------------------------------------------+
//|                                                  Jesse's Bot.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"// Define session times
datetime AsiaSessionStart = TimeCurrent(); // Define appropriately as per session start
datetime AsiaSessionEnd = TimeCurrent() + 7 * 3600 + 30 * 60;
datetime USOpen = TimeCurrent() + 9 * 3600 + 30 * 60;
double entryPrice, stopLoss, takeProfit;
ENUM_ORDER_TYPE TradeType;

double RiskPercent = 2.0; // Risk 2% of account
double RR = 2.0; // 2:1 risk-to-reward

void OnTick() {
   // Print("Current Time: ", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));

    // Check if it's 9:30 EST (use the appropriate offset for your timezone)
    if (TimeCurrent() >= TimeGMTOffset() + 9 * 3600 + 30 * 60 && TimeCurrent() <= TimeGMTOffset() + 9 * 3600 + 40 * 60) {
        Print("Within 9:30-9:40 EST window.");

        // Mark the highs and lows for each session
        double highAsiaLondon = GetHighLow(PERIOD_M5, AsiaSessionStart, AsiaSessionEnd, true);  // Get high for 6:00-7:30
        double lowAsiaLondon = GetHighLow(PERIOD_M5, AsiaSessionStart, AsiaSessionEnd, false);  // Get low for 6:00-7:30
        Print("Asia session high: ", highAsiaLondon, " low: ", lowAsiaLondon);

        // Check if any high or low has been breached since midnight
        if (HasBreached(highAsiaLondon, lowAsiaLondon)) {
            Print("Breached Asia session high/low.");

            // Wait for first M5 FVG to form within 10:00-11:00 or 14:00-15:00 EST
            if (TimeCurrent() >= TimeGMTOffset() + 10 * 3600 && TimeCurrent() <= TimeGMTOffset() + 11 * 3600) {
                Print("Within 10:00-11:00 EST window for FVG detection.");

                // Find first FVG
                if (DetectFVG()) {
                    Print("FVG detected. TradeType: ", TradeType, " Entry Price: ", entryPrice, " Stop Loss: ", stopLoss, " Take Profit: ", takeProfit);

                    // Confirm if FVG aligns with breached high/low
                    if (TradeType == ORDER_TYPE_SELL && iHigh(NULL, PERIOD_M5, 1) > highAsiaLondon) {
                        ExecuteTrade();
                    } else if (TradeType == ORDER_TYPE_BUY && iLow(NULL, PERIOD_M5, 1) < lowAsiaLondon) {
                        ExecuteTrade();
                    }
                } else {
                    Print("No FVG found.");
                }
            }
        } else {
            Print("No breach of Asia session high/low detected.");
        }
    }
}

// Check if a high or low was breached
bool HasBreached(double high, double low) {
    for (int i = 0; i < 24; i++) { // Check last 24 candles
        if (iHigh(NULL, PERIOD_M5, i) > high || iLow(NULL, PERIOD_M5, i) < low) return true;
    }
    return false;
}

// Detect Fair Value Gap (FVG)
bool DetectFVG() {
    // 3-candle formation where middle candle is expansive with a gap
    double high0 = iHigh(NULL, PERIOD_M5, 0);
    double low0 = iLow(NULL, PERIOD_M5, 0);
    double high1 = iHigh(NULL, PERIOD_M5, 1);
    double low1 = iLow(NULL, PERIOD_M5, 1);
    double high2 = iHigh(NULL, PERIOD_M5, 2);
    double low2 = iLow(NULL, PERIOD_M5, 2);

    Print("Checking FVG - High0:", high0, " Low0:", low0, " High1:", high1, " Low1:", low1, " High2:", high2, " Low2:", low2);

    if (high1 < low2 || low1 > high0) {
        TradeType = (low1 > high0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        entryPrice = (high1 + low1) / 2.0;
        stopLoss = (TradeType == ORDER_TYPE_BUY) ? low0 : high0;
        takeProfit = entryPrice + (entryPrice - stopLoss) * RR;
        return true;
    }
    return false;
}

// Execute Trade with 2% of account // Modify the ExecuteTrade() function to use the MetaTrader 5 API
    void ExecuteTrade() {
        double lots = CalculateLotSize();

        MqlTradeRequest request;
        MqlTradeResult result;
        request.action = TRADE_ACTION_DEAL;
        request.symbol = Symbol();
        request.volume = lots;
        request.price = entryPrice;
        request.sl = stopLoss;
        request.tp = takeProfit;
        request.deviation = 2;
        request.type = TradeType;
        request.comment = "FVG Trade";

        if(!OrderSend(request, result)) {
            // Implement error handling
            int lastError = GetLastError();
          

            // Try to recover or adjust the trade parameters
            if (lastError == 130) { // 'Invalid stops' error
                request.sl = NormalizeDouble(request.sl, _Digits);
                request.tp = NormalizeDouble(request.tp, _Digits);
                if(!OrderSend(request, result)) {
                    Print("Retry failed: ");
                } else {
                    Print("Trade executed at: ", entryPrice);
                }
            } else {
                Print("Unhandled error: ", lastError);
            }
        } else {
            Print("Trade executed at: ", entryPrice);
        }
    }

// Calculate lot size based on 2% risk
double CalculateLotSize() {
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    double lotSize = riskAmount / MathAbs(entryPrice - stopLoss);
    return NormalizeDouble(lotSize, 2); // Adjust to minimum lot size for broker
}

// Helper function to get the high or low of a session
double GetHighLow(ENUM_TIMEFRAMES period, datetime startTime, datetime endTime, bool isHigh) {
    double value = isHigh ? -DBL_MAX : DBL_MAX;
    for (int i = 0; i < Bars(_Symbol, period); i++) {
        datetime time = iTime(_Symbol, period, i);
        if (time < startTime) break;
        if (time > endTime) continue;
        
        double current = isHigh ? iHigh(_Symbol, period, i) : iLow(_Symbol, period, i);
        value = isHigh ? MathMax(value, current) : MathMin(value, current);
    }
    return value;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                    FVG_Trading.mql5 |
//+------------------------------------------------------------------+