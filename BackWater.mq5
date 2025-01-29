//+------------------------------------------------------------------+
//|                                                    BackWater.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| IFVG Trading Bot for MetaTrader 5                               |
//| Detects FVG and IFVG, trades based on price action & structure |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

// Parameters
input double LotSize = 0.1;
input int FVG_Lookback = 20;    // Lookback period for FVG detection
input double Min_FVG_Size = 5;  // Minimum gap size in pips
input int StopLoss = 20;        // SL in pips
input int TakeProfit = 50;      // TP in pips
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5; // Execution timeframe

// Function to detect Fair Value Gap (FVG)
bool DetectFVG(double &fvgLow, double &fvgHigh) {
    MqlRates priceData[];
    ArraySetAsSeries(priceData, true);
    if (CopyRates(Symbol(), Timeframe, 0, FVG_Lookback, priceData) <= 0) {
        return false;
    }
    
    for (int i = 2; i < FVG_Lookback; i++) {
        double candle1Low = priceData[i].low;
        double candle2High = priceData[i-1].high;
        double candle3Low = priceData[i-2].low;
        
        if (candle1Low > candle2High && candle3Low > candle2High) {
            fvgLow = candle2High;
            fvgHigh = candle1Low;
            return true;
        }
    }
    return false;
}

// Function to detect Inverse Fair Value Gap (IFVG)
bool DetectIFVG(double fvgLow, double fvgHigh) {
    double closePrice = iClose(Symbol(), Timeframe, 1);
    if (closePrice < fvgLow && closePrice > fvgHigh) {
        return true; // IFVG confirmed
    }
    return false;
}

// Function to check macro trend (simple moving average method)
bool MacroTrend() {
    int maFastHandle = iMA(Symbol(), Timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    int maSlowHandle = iMA(Symbol(), Timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    double maFast[1], maSlow[1];
    CopyBuffer(maFastHandle, 0, 0, 1, maFast);
    CopyBuffer(maSlowHandle, 0, 0, 1, maSlow);
    
    return (maFast[0] > maSlow[0]); // Uptrend if true, downtrend if false
}
// Function to execute trades
void ExecuteTrade(bool isFVG, bool isIFVG) {
    double sl, tp, entryPrice;
    bool uptrend = MacroTrend();
    double askPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bidPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    if (isFVG) {
        entryPrice = askPrice;
        sl = entryPrice - StopLoss * _Point;
        tp = entryPrice + TakeProfit * _Point;
        if (uptrend) trade.Buy(LotSize, Symbol(), entryPrice, sl, tp);
        else trade.Sell(LotSize, Symbol(), entryPrice, sl, tp);
    }
    
    if (isIFVG) {
        entryPrice = bidPrice;
        sl = entryPrice + StopLoss * _Point;
        tp = entryPrice - TakeProfit * _Point;
        if (!uptrend) trade.Buy(LotSize, Symbol(), entryPrice, sl, tp);
        else trade.Sell(LotSize, Symbol(), entryPrice, sl, tp);
    }
}

// OnTick Function (Runs Every Tick)
void OnTick() {
    double fvgLow, fvgHigh;
    bool isFVG = DetectFVG(fvgLow, fvgHigh);
    bool isIFVG = isFVG ? DetectIFVG(fvgLow, fvgHigh) : false;
    
    if (isFVG || isIFVG) ExecuteTrade(isFVG, isIFVG);
}
