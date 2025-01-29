//+------------------------------------------------------------------+
//|                                          TrendlineBreakoutEA.mq5   |
//|                                                                    |
//|                                     Copyright 2024, Your Name Here  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Input parameters for trend analysis
input int      LookbackPeriods = 20;      // Number of periods to analyze trend
input int      TrendStrength = 3;         // Minimum number of points to confirm trend

// Risk management parameters
input double   RiskPercent = 1.0;         // Risk per trade as percentage of balance
input double   MinRiskReward = 2.0;       // Minimum risk-to-reward ratio
input double   MaxRiskPips = 50;          // Maximum risk in pips
input double   MinRiskPips = 10;          // Minimum risk in pips
input double   StopLossMultiplier = 1.5;  // SL distance as multiplier of trend line distance
input double   TakeProfitMultiplier = 3;  // TP distance as multiplier of trend line distance
input bool     UseTrailingStop = true;    // Enable trailing stop
input int      TrailingStopPips = 20;     // Trailing stop distance in pips
input bool     BreakEvenEnabled = true;   // Enable break even feature
input int      BreakEvenPips = 30;        // Pips needed to move stop to break even
input int      BreakEvenBuffer = 5;       // Buffer pips above break even

// Global variables
int handle;
double upperTrendline[];
double lowerTrendline[];
datetime lastTradeTime;
int magicNumber = 12345;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize arrays
    ArraySetAsSeries(upperTrendline, true);
    ArraySetAsSeries(lowerTrendline, true);
    
    lastTradeTime = 0;
    
    // Validate input parameters
    if(MinRiskReward <= 1.0)
    {
        Print("Error: Minimum risk-to-reward ratio must be greater than 1.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(MaxRiskPips <= MinRiskPips)
    {
        Print("Error: Maximum risk pips must be greater than minimum risk pips");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ArrayFree(upperTrendline);
    ArrayFree(lowerTrendline);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // Skip if not enough bars
    if(Bars(_Symbol, PERIOD_CURRENT) < LookbackPeriods) return;
    
    // Update trendlines
    if(!UpdateTrendlines()) return;
    
    // Check for breakouts and manage trades
    CheckBreakouts();
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Calculate and update trendlines                                    |
//+------------------------------------------------------------------+
bool UpdateTrendlines()
{
    int counted_bars = LookbackPeriods;
    ArrayResize(upperTrendline, counted_bars);
    ArrayResize(lowerTrendline, counted_bars);
    
    // Find swing highs and lows
    double highestHigh = 0, lowestLow = DBL_MAX;
    int highestBar = 0, lowestBar = 0;
    
    for(int i = 0; i < counted_bars; i++)
    {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        
        if(high > highestHigh)
        {
            highestHigh = high;
            highestBar = i;
        }
        
        if(low < lowestLow)
        {
            lowestLow = low;
            lowestBar = i;
        }
    }
    
    // Calculate trendline slopes
    double upperSlope = CalculateSlope(highestBar, highestHigh, counted_bars);
    double lowerSlope = CalculateSlope(lowestBar, lowestLow, counted_bars);
    
    // Plot trendlines
    for(int i = 0; i < counted_bars; i++)
    {
        upperTrendline[i] = highestHigh - (upperSlope * i);
        lowerTrendline[i] = lowestLow - (lowerSlope * i);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate slope for trendline                                      |
//+------------------------------------------------------------------+
double CalculateSlope(int startBar, double startPrice, int periods)
{
    double endPrice;
    int endBar = startBar + periods - 1;
    
    if(startBar < periods)
        endPrice = startPrice * 0.9; // Approximate slope
    else
        endPrice = iClose(_Symbol, PERIOD_CURRENT, endBar);
    
    return (endPrice - startPrice) / (endBar - startBar);
}

//+------------------------------------------------------------------+
//| Check for breakouts and execute trades                            |
//+------------------------------------------------------------------+
void CheckBreakouts()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double previousClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    
    // Check for upward breakout
    if(previousClose <= upperTrendline[1] && currentPrice > upperTrendline[0])
    {
        if(IsNewTrade())
            ExecuteTrade(ORDER_TYPE_BUY);
    }
    
    // Check for downward breakout
    if(previousClose >= lowerTrendline[1] && currentPrice < lowerTrendline[0])
    {
        if(IsNewTrade())
            ExecuteTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Execute trade with enhanced risk management                        |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    double stopLoss, takeProfit;
    double entryPrice = (orderType == ORDER_TYPE_BUY) ? 
        SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate initial stop loss based on trendline
    if(orderType == ORDER_TYPE_BUY)
        stopLoss = lowerTrendline[0];
    else
        stopLoss = upperTrendline[0];
    
    // Validate stop loss distance
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    double stopPips = stopDistance / pipSize;
    
    // Adjust stop loss if outside acceptable range
    if(stopPips > MaxRiskPips)
    {
        stopDistance = MaxRiskPips * pipSize;
        stopLoss = (orderType == ORDER_TYPE_BUY) ? 
            entryPrice - stopDistance : 
            entryPrice + stopDistance;
    }
    else if(stopPips < MinRiskPips)
    {
        stopDistance = MinRiskPips * pipSize;
        stopLoss = (orderType == ORDER_TYPE_BUY) ? 
            entryPrice - stopDistance : 
            entryPrice + stopDistance;
    }
    
    // Calculate take profit based on R:R ratio
    double targetDistance = stopDistance * MinRiskReward;
    takeProfit = (orderType == ORDER_TYPE_BUY) ? 
        entryPrice + targetDistance : 
        entryPrice - targetDistance;
    
    // Calculate position size based on risk
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100);
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double distance = MathAbs(entryPrice - stopLoss) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double lotSize = NormalizeDouble(riskAmount / (distance * pipValue), 2);
    
    // Validate lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Execute trade
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 5;
    request.magic = magicNumber;
    
    if(!OrderSend(request, result))
        Print("OrderSend error: ", GetLastError());
    else
    {
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Check if enough time has passed since last trade                  |
//+------------------------------------------------------------------+
bool IsNewTrade()
{
    if(TimeCurrent() - lastTradeTime < PeriodSeconds(PERIOD_CURRENT))
        return false;
    return true;
}

//+------------------------------------------------------------------+
//| Manage open trades with trailing stop and break even              |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
                continue;
            
            double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Break even logic
            if(BreakEvenEnabled && currentSL != positionOpenPrice)
            {
                double pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
                double profitPips = (posType == POSITION_TYPE_BUY) ?
                    (currentPrice - positionOpenPrice) / pipSize :
                    (positionOpenPrice - currentPrice) / pipSize;
                
                if(profitPips >= BreakEvenPips)
                {
                    double newSL = positionOpenPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * 
                                  (BreakEvenBuffer * pipSize);
                    
                    if((posType == POSITION_TYPE_BUY && newSL > currentSL) ||
                       (posType == POSITION_TYPE_SELL && newSL < currentSL))
                    {
                        ModifyPosition(PositionGetTicket(i), newSL);
                    }
                }
            }
            
            // Trailing stop logic
            if(UseTrailingStop)
            {
                double pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
                double trailingDistance = TrailingStopPips * pipSize;
                
                if(posType == POSITION_TYPE_BUY)
                {
                    double newSL = currentPrice - trailingDistance;
                    if(newSL > currentSL)
                        ModifyPosition(PositionGetTicket(i), newSL);
                }
                else
                {
                    double newSL = currentPrice + trailingDistance;
                    if(newSL < currentSL || currentSL == 0)
                        ModifyPosition(PositionGetTicket(i), newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify position's stop loss                                       |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_MODIFY;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP);
    
    return OrderSend(request, result);
}
//slow but profitable