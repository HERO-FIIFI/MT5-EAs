//+------------------------------------------------------------------+
//|                                                    EnhancedGenQ.mq5 |
//|                                    Copyright 2024, Your Name        |
//|                                    https://www.yourwebsite.com      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

// Enumeration for trading sessions
enum TRADING_SESSION {
    LONDON_OPEN = 3,    // London Open (3:00-4:00 AM EST)
    NY_AM = 10,        // NY AM Session (10:00-11:00 AM EST)
    NY_PM = 14         // NY PM Session (2:00-3:00 PM EST)
};

// Input parameters with descriptions
input group "Trading Parameters"
input double LotSize = 0.01;              // Position size in lots
input int StopLoss = 50;                  // Stop loss in points
input int TakeProfit = 100;               // Take profit in points
input bool UseBreakEven = true;           // Enable break-even feature
input double BreakEvenTrigger = 0.5;      // Profit ratio to trigger break-even

input group "Session Settings"
input bool UseLondonOpen = true;          // Trade London session
input bool UseNYAMSession = true;         // Trade NY AM session
input bool UseNYPMSession = true;         // Trade NY PM session
input int SessionDurationMins = 60;       // Session duration in minutes

input group "Analysis Settings"
input int FVGPeriods = 3;                 // Periods for FVG calculation
input int LiquidityThreshold = 20;        // Periods to check for liquidity
input int MinutesBetweenTrades = 5;       // Minimum time between trades
input double MinFVGSize = 10;             // Minimum FVG size in points

// Global variables
datetime lastTradeTime = 0;
int magicNumber = 123456;
bool isNewBar = false;

//+------------------------------------------------------------------+
//| Custom Trade Result structure                                      |
//+------------------------------------------------------------------+
struct TradeResult {
    bool success;
    string message;
    ulong ticket;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
    // Validate inputs
    if (LotSize <= 0 || StopLoss <= 0 || TakeProfit <= 0) {
        PrintFormat("Invalid inputs: LotSize=%.2f, SL=%d, TP=%d", LotSize, StopLoss, TakeProfit);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Check if automated trading is enabled
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        Print("Automated trading is not allowed in the terminal");
        return INIT_FAILED;
    }
    
    Print("EnhancedGenQ initialized successfully. Magic Number: ", magicNumber);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    PrintFormat("EnhancedGenQ deinitialized. Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for new bar
    isNewBar = IsNewBar();
    if (!isNewBar) return;  // Only process on new bars
    
    // Check trading conditions
    if (!IsSilverBulletTime()) return;
    
    FVGData fvg = CalculateFVG();
    if (!fvg.isValid) return;
    
    if (!IsLiquidityNearby()) return;
    
    // Check time between trades
    if (TimeCurrent() - lastTradeTime <= MinutesBetweenTrades * 60) return;
    
    // Open trade based on FVG direction
    TradeResult result = OpenTrade(fvg.direction);
    if (result.success) {
        lastTradeTime = TimeCurrent();
        PrintFormat("Trade opened successfully. Ticket: %d", result.ticket);
    }
    
    // Manage existing positions
    if (UseBreakEven) ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Check for new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar() {
    static datetime lastBar = 0;
    datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
    
    if (lastBar != currentBar) {
        lastBar = currentBar;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if it's trading session time                                |
//+------------------------------------------------------------------+
bool IsSilverBulletTime() {
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    // Check if within session duration
    int minutesPastHour = timeStruct.min;
    if (minutesPastHour >= SessionDurationMins) return false;
    
    // Check active sessions
    if (UseLondonOpen && timeStruct.hour == LONDON_OPEN) return true;
    if (UseNYAMSession && timeStruct.hour == NY_AM) return true;
    if (UseNYPMSession && timeStruct.hour == NY_PM) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| FVG Data Structure                                                |
//+------------------------------------------------------------------+
struct FVGData {
    bool isValid;
    int direction;  // 1 for bullish, -1 for bearish
    double size;
};

//+------------------------------------------------------------------+
//| Calculate Fair Value Gap                                          |
//+------------------------------------------------------------------+
FVGData CalculateFVG() {
    FVGData result = {false, 0, 0};
    
    double highestHigh = iHigh(Symbol(), PERIOD_CURRENT, iHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, FVGPeriods, 1));
    double lowestLow = iLow(Symbol(), PERIOD_CURRENT, iLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, FVGPeriods, 1));
    double currentOpen = iOpen(Symbol(), PERIOD_CURRENT, 0);
    double previousClose = iClose(Symbol(), PERIOD_CURRENT, 1);
    
    // Calculate FVG size
    double fvgSize = MathAbs(currentOpen - previousClose) / _Point;
    
    // Check if FVG size meets minimum requirement
    if (fvgSize < MinFVGSize) return result;
    
    // Bullish FVG
    if (currentOpen > previousClose && previousClose < lowestLow) {
        result.isValid = true;
        result.direction = 1;
        result.size = fvgSize;
    }
    // Bearish FVG
    else if (currentOpen < previousClose && previousClose > highestHigh) {
        result.isValid = true;
        result.direction = -1;
        result.size = fvgSize;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check for nearby liquidity                                        |
//+------------------------------------------------------------------+
bool IsLiquidityNearby() {
    double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
    double checkRange = StopLoss * _Point * 0.5;
    
    for (int i = 1; i <= LiquidityThreshold; i++) {
        if (iHigh(Symbol(), PERIOD_CURRENT, i) > currentPrice + checkRange || 
            iLow(Symbol(), PERIOD_CURRENT, i) < currentPrice - checkRange) 
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open a trade based on direction                                   |
//+------------------------------------------------------------------+
TradeResult OpenTrade(int direction) {
    TradeResult result = {false, "", 0};
    
    int cmd = (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double price = (cmd == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = (cmd == ORDER_TYPE_BUY) ? price - StopLoss * _Point : price + StopLoss * _Point;
    double tp = (cmd == ORDER_TYPE_BUY) ? price + TakeProfit * _Point : price - TakeProfit * _Point;
    
    MqlTradeRequest request = {};
    MqlTradeResult tradeResult = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = LotSize;
    request.type = cmd;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.magic = magicNumber;
    request.comment = "GenQ " + (cmd == ORDER_TYPE_BUY ? "Buy" : "Sell");
    
    if (!OrderSend(request, tradeResult)) {
        result.message = "Error opening trade: " + IntegerToString(GetLastError());
        return result;
    }
    
    result.success = true;
    result.ticket = tradeResult.order;
    result.message = "Trade opened successfully";
    return result;
}

//+------------------------------------------------------------------+
//| Manage open trades                                                |
//+------------------------------------------------------------------+
void ManageOpenTrades() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        
        if (PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
        
        // Calculate current profit ratio
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double riskAmount = MathAbs(entryPrice - stopLoss);
        double profitAmount = MathAbs(currentPrice - entryPrice);
        double profitRatio = profitAmount / riskAmount;
        
        // Move to break-even if profit ratio exceeds trigger
        if (profitRatio >= BreakEvenTrigger && stopLoss != entryPrice) {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = entryPrice;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if (!OrderSend(request, result)) {
                PrintFormat("Error moving stop loss to break-even: %d", GetLastError());
            }
        }
    }
}
//+------------------------------------------------------------------+
//No trades