//+------------------------------------------------------------------+
//|                                      Gloria's market flogger.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"


//+------------------------------------------------------------------+
//| Market Structure Analysis and Trading Strategy                      |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

// Include required files
#include <Trade\Trade.mqh>

// Input parameters
input ENUM_TIMEFRAMES TimeFrame4h = PERIOD_H4;     // 4-hour timeframe for trend
input ENUM_TIMEFRAMES TimeFrame1h = PERIOD_H1;     // 1-hour timeframe for analysis
input double  RiskPercent = 1.0;           // Risk percentage per trade
input double  RRRatio    = 3.0;            // Risk:Reward ratio
input int     FiboPeriod = 20;             // Period for Fibonacci calculations
input int     LookbackPeriods = 50;        // Periods to analyze structure

// Structure for Point of Interest (POI)
struct POI {
    double price;
    datetime time;
    bool isSupply;
    bool isDemand;
    bool hasFVG;
};

// Global variables
POI g_POIs[];
double g_FibLevels[];
bool g_TrendUp = false;
CTrade trade;

// Price buffers
double supplyBuffer[];
double demandBuffer[];
double fvgBuffer[];
MqlRates rates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize buffers
    ArraySetAsSeries(supplyBuffer, true);
    ArraySetAsSeries(demandBuffer, true);
    ArraySetAsSeries(fvgBuffer, true);
    ArraySetAsSeries(rates, true);
    
    return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Calculate Stop Loss level                                          |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isBuy) {
    // Get ATR value using correct parameter count
    int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(atrHandle == INVALID_HANDLE) {
        Print("Error creating ATR indicator handle: ", GetLastError());
        return 0.0;
    }
    
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    
    // Copy ATR values
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0) {
        Print("Error copying ATR values: ", GetLastError());
        return 0.0;
    }
    
    // Release the indicator handle
    IndicatorRelease(atrHandle);
    
    if(isBuy)
        return SymbolInfoDouble(_Symbol, SYMBOL_BID) - (atrBuffer[0] * 1.5);
    else
        return SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (atrBuffer[0] * 1.5);
}

// [Rest of the code remains exactly the same as in the previous artifact]

//+------------------------------------------------------------------+
//| Calculate Take Profit level                                        |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double stopLoss) {
    double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopDistance = MathAbs(entry - stopLoss);
    
    if(isBuy)
        return entry + (stopDistance * RRRatio);
    else
        return entry - (stopDistance * RRRatio);
}

//+------------------------------------------------------------------+
//| Check 4-hour trend                                                 |
//+------------------------------------------------------------------+
bool AnalyzeTrend() {
    double ma20[], ma50[];
    ArraySetAsSeries(ma20, true);
    ArraySetAsSeries(ma50, true);
    
    CopyBuffer(iMA(_Symbol, TimeFrame4h, 20, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, ma20);
    CopyBuffer(iMA(_Symbol, TimeFrame4h, 50, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, ma50);
    
    g_TrendUp = (ma20[0] > ma50[0]);
    return g_TrendUp;
}

//+------------------------------------------------------------------+
//| Identify Fair Value Gaps (FVG)                                     |
//+------------------------------------------------------------------+
void FindFVGs() {
    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, LookbackPeriods, rates) <= 0) return;
    
    ArrayResize(fvgBuffer, ArraySize(rates));
    
    for(int i = 2; i < ArraySize(rates)-1; i++) {
        double highPrev = rates[i+1].high;
        double lowNext = rates[i-1].low;
        
        // Bullish FVG
        if(lowNext > highPrev) {
            fvgBuffer[i] = lowNext;
        }
        // Bearish FVG
        if(rates[i-1].high < rates[i+1].low) {
            fvgBuffer[i] = rates[i-1].high;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if price is at swing high                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(int index) {
    return (rates[index].high > rates[index+1].high && 
            rates[index].high > rates[index-1].high);
}

//+------------------------------------------------------------------+
//| Check if price is at swing low                                     |
//+------------------------------------------------------------------+
bool IsSwingLow(int index) {
    return (rates[index].low < rates[index+1].low && 
            rates[index].low < rates[index-1].low);
}

//+------------------------------------------------------------------+
//| Identify Supply and Demand zones                                   |
//+------------------------------------------------------------------+
void FindSupplyDemandZones() {
    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, LookbackPeriods, rates) <= 0) return;
    
    ArrayResize(supplyBuffer, ArraySize(rates));
    ArrayResize(demandBuffer, ArraySize(rates));
    
    for(int i = 1; i < ArraySize(rates)-1; i++) {
        // Supply zone identification
        if(IsSwingHigh(i)) {
            supplyBuffer[i] = rates[i].high;
            ArrayResize(g_POIs, ArraySize(g_POIs) + 1);
            int idx = ArraySize(g_POIs) - 1;
            g_POIs[idx].price = rates[i].high;
            g_POIs[idx].time = rates[i].time;
            g_POIs[idx].isSupply = true;
        }
        
        // Demand zone identification
        if(IsSwingLow(i)) {
            demandBuffer[i] = rates[i].low;
            ArrayResize(g_POIs, ArraySize(g_POIs) + 1);
            int idx = ArraySize(g_POIs) - 1;
            g_POIs[idx].price = rates[i].low;
            g_POIs[idx].time = rates[i].time;
            g_POIs[idx].isDemand = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if price taps into POI                                       |
//+------------------------------------------------------------------+
bool CheckPOITap() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(g_POIs); i++) {
        double poiLevel = g_POIs[i].price;
        double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
        
        if(MathAbs(currentPrice - poiLevel) <= tolerance) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                              |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stopLoss) {
    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = accountEquity * (RiskPercent / 100);
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopPoints = MathAbs(stopLoss - currentPrice) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    return NormalizeDouble((riskAmount / (stopPoints * tickValue)), 2);
}


//works fine but we need to fix the lots for synthetics

//+------------------------------------------------------------------+
//| Check for nearby liquidity                                         |
//+------------------------------------------------------------------+
bool HasNearbyLiquidity() {
    return false; // Implement your liquidity check logic here
}

//+------------------------------------------------------------------+
//| Check for impulsive move                                          |
//+------------------------------------------------------------------+
bool IsImpulsiveMove() {
    return true; // Implement your impulsive move check logic here
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if we're in a new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(lastBar == currentBar) return;
    lastBar = currentBar;
    
    // Update price data
    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, LookbackPeriods, rates) <= 0) return;
    
    // 1. Analyze 4-hour trend
    bool trendUp = AnalyzeTrend();
    
    // 2. Analyze 1-hour market structure
    FindSupplyDemandZones();
    FindFVGs();
    
    // 3. Check for POI tap
    if(CheckPOITap()) {
        // 4. Check if conditions align for trade
        if(ValidateTradeSetup()) {
            // Calculate stop loss and take profit
            bool isBuy = trendUp;
            double stopLoss = CalculateStopLoss(isBuy);
            double takeProfit = CalculateTakeProfit(isBuy, stopLoss);
            
            // Calculate position size
            double lots = CalculatePositionSize(stopLoss);
            
            // Execute trade
            if(isBuy) {
                trade.Buy(lots, _Symbol, 0, stopLoss, takeProfit, "Market Structure Trade");
            } else {
                trade.Sell(lots, _Symbol, 0, stopLoss, takeProfit, "Market Structure Trade");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Validate trade setup                                               |
//+------------------------------------------------------------------+
bool ValidateTradeSetup() {
    if(!CheckPOITap()) return false;
    
    double closes[];
    ArraySetAsSeries(closes, true);
    CopyClose(_Symbol, PERIOD_CURRENT, 0, 21, closes);
    
    if(g_TrendUp && closes[0] < closes[20]) return false;
    if(!g_TrendUp && closes[0] > closes[20]) return false;
    
    if(HasNearbyLiquidity()) return false;
    if(!IsImpulsiveMove()) return false;
    
    return true;
}

//massive loss review