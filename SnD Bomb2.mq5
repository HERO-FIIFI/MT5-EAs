//+------------------------------------------------------------------+
//|                                                    SnD Bomb2.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"//


//+------------------------------------------------------------------+
//|                     DnS Strategy                                    |
//+------------------------------------------------------------------+
#property copyright "Trading Strategy"
#property link      ""
#property version   "1.00"
#property strict

// Input parameters
input int      LookbackPeriods = 20;    // Periods to identify S/R zones
input int      ZoneStrength    = 3;     // Minimum touches to confirm zone
input double   ZoneWidth       = 100;    // Width of zones in points
input double   RiskPercent     = 2.0;    // Risk per trade (%)
input double   RRRatio        = 2.0;    // Reward to Risk ratio

// Global variables
double accountBalance;
double riskAmount;
double stopLoss;
double takeProfit;

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have any open positions
   if(PositionsTotal() > 0) return;
   
   // Get current market data
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Identify supply and demand zones
   double supplyZone = FindSupplyZone();
   double demandZone = FindDemandZone();
   
   // Calculate position size based on risk
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   riskAmount = accountBalance * (RiskPercent / 100);
   
   // Check for trade signals
   if(IsInSupplyZone(currentPrice, supplyZone))
   {
      // Short entry logic
      stopLoss = supplyZone + (ZoneWidth * Point());
      takeProfit = currentPrice - (RRRatio * (stopLoss - currentPrice));
      
      double lotSize = CalculateLotSize(currentPrice, stopLoss, riskAmount);
      OpenShort(lotSize, stopLoss, takeProfit);
   }
   
   if(IsInDemandZone(currentPrice, demandZone))
   {
      // Long entry logic
      stopLoss = demandZone - (ZoneWidth * Point());
      takeProfit = currentPrice + (RRRatio * (currentPrice - stopLoss));
      
      double lotSize = CalculateLotSize(currentPrice, stopLoss, riskAmount);
      OpenLong(lotSize, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Find Supply Zone                                                   |
//+------------------------------------------------------------------+
double FindSupplyZone()
{
   double supplyZone = 0;
   int touches = 0;
   
   for(int i = 0; i < LookbackPeriods; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      
      // Check if price rejected from this level multiple times
      for(int j = 0; j < LookbackPeriods; j++)
      {
         if(MathAbs(high - iHigh(_Symbol, PERIOD_CURRENT, j)) <= ZoneWidth * Point())
         {
            touches++;
         }
      }
      
      if(touches >= ZoneStrength)
      {
         supplyZone = high;
         break;
      }
      touches = 0;
   }
   
   return supplyZone;
}

//+------------------------------------------------------------------+
//| Find Demand Zone                                                   |
//+------------------------------------------------------------------+
double FindDemandZone()
{
   double demandZone = 0;
   int touches = 0;
   
   for(int i = 0; i < LookbackPeriods; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      
      // Check if price rejected from this level multiple times
      for(int j = 0; j < LookbackPeriods; j++)
      {
         if(MathAbs(low - iLow(_Symbol, PERIOD_CURRENT, j)) <= ZoneWidth * Point())
         {
            touches++;
         }
      }
      
      if(touches >= ZoneStrength)
      {
         demandZone = low;
         break;
      }
      touches = 0;
   }
   
   return demandZone;
}

//+------------------------------------------------------------------+
//| Check if price is in supply zone                                   |
//+------------------------------------------------------------------+
bool IsInSupplyZone(double price, double zone)
{
   return (MathAbs(price - zone) <= ZoneWidth * Point());
}

//+------------------------------------------------------------------+
//| Check if price is in demand zone                                   |
//+------------------------------------------------------------------+
bool IsInDemandZone(double price, double zone)
{
   return (MathAbs(price - zone) <= ZoneWidth * Point());
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                              |
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double stop, double risk)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double slPoints = MathAbs(entry - stop) / tickSize;
   double lotSize = risk / (slPoints * tickValue);
   
   // Round to valid lot step
   return MathFloor(lotSize / lotStep) * lotStep;
}

//+------------------------------------------------------------------+
//| Open Long Position                                                 |
//+------------------------------------------------------------------+
bool OpenLong(double lots, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 5;
   request.type_filling = ORDER_FILLING_FOK;
   
   bool success = OrderSend(request, result);
   
   if(!success)
   {
      Print("OrderSend error: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open Short Position                                                |
//+------------------------------------------------------------------+
bool OpenShort(double lots, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 5;
   request.type_filling = ORDER_FILLING_FOK;
   
   bool success = OrderSend(request, result);
   
   if(!success)
   {
      Print("OrderSend error: ", GetLastError());
      return false;
   }
   
   return true;
}

//Minimal loss
//Zero Divider issues