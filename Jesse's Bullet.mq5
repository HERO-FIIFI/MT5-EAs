//+------------------------------------------------------------------+
//|                                               Jesse's Bullet.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"


//+------------------------------------------------------------------+
//|                                                    FVG_Trading.mql5 |
//+------------------------------------------------------------------+
#property copyright "2024"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input parameters
input int      RISK_PERCENT = 2;         // Risk percentage per trade
input double   RR_RATIO    = 2.0;        // Risk:Reward ratio for first position
input int      GMT_OFFSET  = -5;         // GMT offset for EST (adjust for DST)

// Global variables
datetime lastTradeDate = 0;
bool tradingEnabled = false;
int magicNumber = 12345;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(magicNumber);
    Print("EA Initialized - Server Time: ", TimeCurrent());
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Convert server time to EST                                        |
//+------------------------------------------------------------------+
datetime ServerToEST(datetime serverTime)
{
    return serverTime + GMT_OFFSET * 3600;
}

//+------------------------------------------------------------------+
//| Check if time is within range                                     |
//+------------------------------------------------------------------+
bool IsWithinTimeRange(datetime serverTime, int startHour, int startMin, int endHour, int endMin)
{
    datetime estTime = ServerToEST(serverTime);
    MqlDateTime dt;
    TimeToStruct(estTime, dt);
    
    int timeMinutes = dt.hour * 60 + dt.min;
    int startMinutes = startHour * 60 + startMin;
    int endMinutes = endHour * 60 + endMin;
    
    bool isWithin = (timeMinutes >= startMinutes && timeMinutes <= endMinutes);
    if(isWithin)
        Print("Time check passed - Current EST: ", dt.hour, ":", dt.min);
    
    return isWithin;
}

//+------------------------------------------------------------------+
//| Check for FVG pattern                                             |
//+------------------------------------------------------------------+
bool IsFVGPattern(int shift, bool& isBearish)
{
    double high1 = iHigh(_Symbol, PERIOD_M5, shift + 2);  // First candle
    double low1 = iLow(_Symbol, PERIOD_M5, shift + 2);
    double high2 = iHigh(_Symbol, PERIOD_M5, shift + 1);  // Middle candle
    double low2 = iLow(_Symbol, PERIOD_M5, shift + 1);
    double high3 = iHigh(_Symbol, PERIOD_M5, shift);      // Last candle
    double low3 = iLow(_Symbol, PERIOD_M5, shift);
    
    // Debug print
    Print("Checking FVG Pattern - Candle Details:");
    Print("First Candle  - High: ", high1, " Low: ", low1);
    Print("Middle Candle - High: ", high2, " Low: ", low2);
    Print("Last Candle   - High: ", high3, " Low: ", low3);
    
    // Bearish FVG
    if (low2 > high3 && low2 > high1)
    {
        isBearish = true;
        Print("Bearish FVG Found!");
        return true;
    }
    
    // Bullish FVG
    if (high2 < low3 && high2 < low1)
    {
        isBearish = false;
        Print("Bullish FVG Found!");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get session high/low prices                                       |
//+------------------------------------------------------------------+
void GetSessionHL(datetime startTime, datetime endTime, double& sessionHigh, double& sessionLow)
{
    sessionHigh = -DBL_MAX;
    sessionLow = DBL_MAX;
    
    for(int i = 0; i < Bars(_Symbol, PERIOD_M5); i++)
    {
        datetime candleTime = iTime(_Symbol, PERIOD_M5, i);
        if(candleTime < startTime) break;
        if(candleTime > endTime) continue;
        
        double high = iHigh(_Symbol, PERIOD_M5, i);
        double low = iLow(_Symbol, PERIOD_M5, i);
        
        if(high > sessionHigh) sessionHigh = high;
        if(low < sessionLow) sessionLow = low;
    }
    
    Print("Session Levels - High: ", sessionHigh, " Low: ", sessionLow);
}

//+------------------------------------------------------------------+
//| Check if session levels have been taken                           |
//+------------------------------------------------------------------+
bool AreSessionLevelsTaken(double sessionHigh, double sessionLow)
{
    datetime currentServerTime = TimeCurrent();
    datetime estMidnight = ServerToEST(currentServerTime);
    MqlDateTime dt;
    TimeToStruct(estMidnight, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    datetime midnight = StructToTime(dt);
    
    bool levelsTaken = false;
    for(int i = 0; i < Bars(_Symbol, PERIOD_M5); i++)
    {
        datetime candleTime = iTime(_Symbol, PERIOD_M5, i);
        if(candleTime < midnight) break;
        
        double high = iHigh(_Symbol, PERIOD_M5, i);
        double low = iLow(_Symbol, PERIOD_M5, i);
        
        if(high > sessionHigh || low < sessionLow)
        {
            Print("Session levels taken - Candle High: ", high, " Low: ", low);
            levelsTaken = true;
            break;
        }
    }
    
    if(!levelsTaken)
        Print("Session levels not yet taken");
    
    return levelsTaken;
}

//+------------------------------------------------------------------+
//| Calculate position size                                           |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stopLoss)
{
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RISK_PERCENT / 100;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopLossPoints = MathAbs(stopLoss - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / tickSize;
    
    double lotSize = NormalizeDouble(riskAmount / (stopLossPoints * tickValue), 2);
    Print("Position Size Calculation - Risk Amount: ", riskAmount, " Lot Size: ", lotSize);
    return lotSize;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentServerTime = TimeCurrent();
    datetime estTime = ServerToEST(currentServerTime);
    MqlDateTime dt;
    TimeToStruct(estTime, dt);
    MqlDateTime lastDt;
    TimeToStruct(lastTradeDate, lastDt);
    
    Print("Current EST Time - ", dt.hour, ":", dt.min);
    
    // Reset trading at 9:30 EST
    if(dt.hour == 9 && dt.min == 30 && dt.day != lastDt.day)
    {
        Print("New trading day started at 9:30 EST");
        tradingEnabled = true;
        lastTradeDate = currentServerTime;
        
        // Get Asia/London session high/low (6:00-7:30 EST)
        MqlDateTime sessionDt;
        TimeToStruct(currentServerTime, sessionDt);
        sessionDt.hour = dt.hour - 3; // 6:00 EST
        sessionDt.min = 0;
        sessionDt.sec = 0;
        datetime sessionStart = StructToTime(sessionDt);
        
        sessionDt.hour = dt.hour - 2; // 7:30 EST
        sessionDt.min = 30;
        datetime sessionEnd = StructToTime(sessionDt);
        
        double sessionHigh, sessionLow;
        GetSessionHL(sessionStart, sessionEnd, sessionHigh, sessionLow);
        
        // Check if levels have been taken
        if(!AreSessionLevelsTaken(sessionHigh, sessionLow))
        {
            Print("Session levels not taken, disabling trading for today");
            tradingEnabled = false;
            return;
        }
    }
    
    if(!tradingEnabled)
    {
        Print("Trading not enabled");
        return;
    }
    
    // Check if we're in valid trading windows (10-11am EST or 2-3pm EST)
    bool validTimeWindow = IsWithinTimeRange(currentServerTime, 10, 0, 11, 0) || 
                          IsWithinTimeRange(currentServerTime, 14, 0, 15, 0);
    
    if(!validTimeWindow)
    {
        Print("Not in valid time window");
        return;
    }
    
    // Check for FVG pattern
    bool isBearish;
    if(!IsFVGPattern(0, isBearish))
    {
        Print("No valid FVG pattern found");
        return;
    }
    
    // Get middle candle price for entry
    double entryPrice = iClose(_Symbol, PERIOD_M5, 1);
    double stopLoss = iHigh(_Symbol, PERIOD_M5, 2); // First candle high for bearish
    
    if(!isBearish)
        stopLoss = iLow(_Symbol, PERIOD_M5, 2); // First candle low for bullish
    
    double takeProfit = entryPrice + (entryPrice - stopLoss) * RR_RATIO;
    if(isBearish)
        takeProfit = entryPrice - (stopLoss - entryPrice) * RR_RATIO;
    
    double lotSize = CalculatePositionSize(stopLoss);
    
    Print("Trade Setup - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit);
    
    // Open two positions
    if(isBearish)
    {
        // Position 1 with fixed RR
        if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "FVG Trade 1"))
            Print("Bearish Position 1 opened successfully");
        else
            Print("Failed to open Bearish Position 1. Error: ", GetLastError());
        
        // Position 2 with EOD close
        if(trade.Sell(lotSize, _Symbol, 0, stopLoss, 0, "FVG Trade 2"))
            Print("Bearish Position 2 opened successfully");
        else
            Print("Failed to open Bearish Position 2. Error: ", GetLastError());
    }
    else
    {
        // Position 1 with fixed RR
        if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "FVG Trade 1"))
            Print("Bullish Position 1 opened successfully");
        else
            Print("Failed to open Bullish Position 1. Error: ", GetLastError());
        
        // Position 2 with EOD close
        if(trade.Buy(lotSize, _Symbol, 0, stopLoss, 0, "FVG Trade 2"))
            Print("Bullish Position 2 opened successfully");
        else
            Print("Failed to open Bullish Position 2. Error: ", GetLastError());
    }
    
    tradingEnabled = false; // Disable trading for the day
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA Deinitialized - Reason: ", reason);
    // Close any remaining positions at end of day
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket != 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
                if(trade.PositionClose(ticket))
                    Print("Position closed successfully: ", ticket);
                else
                    Print("Failed to close position: ", ticket, " Error: ", GetLastError());
            }
        }
    }
}
