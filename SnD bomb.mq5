//+------------------------------------------------------------------+
//|                                                     SnD bomb.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input double RiskPercent = 2.0;         // Risk per trade in percentage
input double RewardRiskRatio = 2.0;     // Reward to risk ratio
input int ATRPeriod = 14;               // ATR period for zone calculation
input int LookBackPeriod = 50;          // Period to look back for zones

// Global variables
double SupplyZone, DemandZone, StopLoss, TakeProfit;
ulong OrderTicket;

//+------------------------------------------------------------------+
//| Calculate Account Risk based on percentage                       |
//+------------------------------------------------------------------+
double CalculateRisk(double riskPercent) {
    return AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0);
}

//+------------------------------------------------------------------+
//| Calculate Optimal Lot Size                                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips) {
    double risk = CalculateRisk(RiskPercent);
    double pipValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    return NormalizeDouble(risk / (stopLossPips * pipValue), 2);
}

//+------------------------------------------------------------------+
//| Detect Supply and Demand Zones                                   |
//+------------------------------------------------------------------+
void DetectZones() {
    double high = iHigh(Symbol(), PERIOD_CURRENT, iHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, LookBackPeriod, 0));
    double low = iLow(Symbol(), PERIOD_CURRENT, iLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, LookBackPeriod, 0));
    
    SupplyZone = high;
    DemandZone = low;
}

//+------------------------------------------------------------------+
//| Place Trade with Risk Management                                 |
//+------------------------------------------------------------------+
void PlaceTrade(ENUM_ORDER_TYPE direction) {
    double atr[];
    ArraySetAsSeries(atr, true);
    int copied = CopyBuffer(iATR(Symbol(), PERIOD_CURRENT, ATRPeriod), 0, 0, 1, atr);
    if(copied <= 0) return;
    
    double entryPrice = (direction == ORDER_TYPE_BUY) ? DemandZone : SupplyZone;
    StopLoss = (direction == ORDER_TYPE_BUY) ? entryPrice - atr[0] : entryPrice + atr[0];
    TakeProfit = entryPrice + ((entryPrice - StopLoss) * RewardRiskRatio * (direction == ORDER_TYPE_BUY ? 1 : -1));
    
    double stopLossPips = MathAbs(entryPrice - StopLoss) / Point();
    double lotSize = CalculateLotSize(stopLossPips);
    
    // Check if there's an existing order
    if(PositionSelect(Symbol())) {
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    bool sameDirection = (direction == ORDER_TYPE_BUY && posType == POSITION_TYPE_BUY) ||
                         (direction == ORDER_TYPE_SELL && posType == POSITION_TYPE_SELL);
    if(sameDirection) {
        Print("Trade already exists.");
        return;
    }
}

    
    // Send the order
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.type = direction;
    request.volume = lotSize;
    request.price = entryPrice;
    request.sl = StopLoss;
    request.tp = TakeProfit;
    request.comment = "SnD Strategy";
    
    if(!OrderSend(request, result)) {
        Print("Error opening order: ", GetLastError());
    } else {
        Print("Order placed: Ticket ", result.order, " Entry: ", entryPrice, " SL: ", StopLoss, " TP: ", TakeProfit);
        OrderTicket = result.order;
    }
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    DetectZones();
    
    double close = iClose(Symbol(), PERIOD_CURRENT, 1);
    double open = iOpen(Symbol(), PERIOD_CURRENT, 1);
    
    if(close < SupplyZone && open > SupplyZone) {
        PlaceTrade(ORDER_TYPE_SELL);
    } else if(close > DemandZone && open < DemandZone) {
        PlaceTrade(ORDER_TYPE_BUY);
    }
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Strategy deinitialized.");
}