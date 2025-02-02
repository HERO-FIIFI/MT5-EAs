//+------------------------------------------------------------------+
//|                                                     Pullback.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

extern bool   Use_TP_In_Money=false;
extern double TP_In_Money=10;
extern bool   Use_TP_In_percent=false;
extern double TP_In_Percent=10;
//--------------------------------------------------------------------
/////////////////////////////////////////////////////////////////////////////////
input    string               txt32                    = "------------[Money Trailing Stop]---------------"; //———————————————————————————————————————————
input    bool                 Enable_Trailing           = true; //Enable_Trailing
input    double               Take_Profit_Money       = 40.0; //Take Profit In Money (in current currency)
input    double               Stop_Loss_Money         = 10; //Stop Loss In Money(in current currency)
/////////////////////////////////////////////////////////////////////////////////
//---------------------------------------------------------------------------------
//--------------------------------------------------------------------
extern bool         Exit=false;//Enable Exit strategy
extern double      IncreaseFactor=0.001;   //IncreaseFactor
extern int         CandlesToRetrace=10;    //Num.Of Candles For Divergence
extern double      Lots=0.01;              //Lots size
extern double      LotExponent = 1.44;     //Lots size Exponent
extern double      Stop_Loss=20;           //Stop Loss
extern int         MagicNumber=1234;       //MagicNumber
input double       Take_Profit=50;          //TakeProfit
extern int         FastMA=6;             //FastMA
extern int         SlowMA=85;            //SlowMA
extern double      Mom_Sell=0.3;           //Momentum_Sell
extern double      Mom_Buy=0.3;            //Momentum_Buy
input bool         UseEquityStop = true;  //Use Equity Stop
input double       TotalEquityRisk = 1.0; //Total Equity Risk
input int          Max_Trades=10;
extern double      TrailingStop=40;        //TrailingStop
input bool            USEMOVETOBREAKEVEN=true;//Enable "no loss"
input double          WHENTOMOVETOBE=30;      //When to move break even
input double          PIPSTOMOVESL=30;         //How much pips to move sl

int           err;
int total=0;
double
Lot,Dmax,Dmin,// Amount of lots in a selected order
    Lts,                             // Amount of lots in an opened order
    Min_Lot,                         // Minimal amount of lots
    Step,                            // Step of lot size change
    Free,                            // Current free margin
    One_Lot,                         // Price of one lot
    Price,                           // Price of a selected order,
    pips,
    MA_1,MA_2,MACD_SIGNAL;
int Type,freeze_level,Spread;
double priceopen,stoploss,takeprofit;

int orderticket;
int INDEX2=0;
double PROFIT_SUM1=0;
double PROFIT_SUM2=0;
int
Period_MA_2,  Period_MA_3,       // Calculation periods of MA for other timefr.
              Period_MA_02, Period_MA_03,      // Calculation periods of supp. MAs
              K2,K3,T,L;
//---

double AccountEquityHighAmt,PrevEquity;
int OnInit()
  {
  switch(Period())                 // Calculating coefficient for..
     {                              // .. different timeframes
      case     1: K2=5;K3=15;T=PERIOD_M15; break;// Timeframe M1
      case     5: K2=3;K3= 6;T=PERIOD_M30; break;// Timeframe M5
      case    15: K2=2;K3= 4;T=PERIOD_H1; break;// Timeframe M15
      case    30: K2=2;K3= 8;T=PERIOD_H4; break;// Timeframe M30
      case    60: K2=4;K3=24;T=PERIOD_D1; break;// Timeframe H1
      case   240: K2=6;K3=42;T=PERIOD_W1; break;// Timeframe H4
      case  1440: K2=7;K3=30;T=PERIOD_MN1; break;// Timeframe D1
      case 10080: K2=4;K3=12; break;// Timeframe W1
      case 43200: K2=3;K3=12; break;// Timeframe MN
     }

   double ticksize=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(ticksize==0.00001 || ticksize==0.001)
      pips=ticksize*10;
   else
      pips=ticksize;
   return(INIT_SUCCEEDED);
//--- distance from the activation price, within which it is not allowed to modify orders and positions
   freeze_level=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze_level!=0)
     {
      PrintFormat("SYMBOL_TRADE_FREEZE_LEVEL=%d: order or position modification is not allowed,"+
                  " if there are %d points to the activation price",freeze_level,freeze_level);
     }
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
  }
void OnTick(void)
  {  if(Exit=true)
  {   Close_SELL();
  }if(Use_TP_In_Money)
     { Take_Profit_In_Money();} if(Use_TP_In_percent)
     { Take_Profit_In_percent();}if(Enable_Trailing==true)
     {TRAIL_PROFIT_IN_MONEY2();}
// double MacdCurrent,MacdPrevious;// double SignalCurrent,SignalPrevious;//double MaCurrent,MaPrevious;
   int   ticket=0;
   double AveragePrice=0;
   double Count=0;
   double CurrentPairProfit=CalculateProfit();
   static datetime dtBarCurrent=WRONG_VALUE;
   datetime dtBarPrevious=dtBarCurrent;
   dtBarCurrent=(datetime) SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
   bool NewBarFlag=(dtBarCurrent!=dtBarPrevious);
   if(NewBarFlag)
     {
      if(UseEquityStop)
        {
         if(CurrentPairProfit<0.0 && MathAbs(CurrentPairProfit)>TotalEquityRisk/100.0*AccountEquityHigh())
           {
            CloseThisSymbolAll();
            Print("Closed All due to Stop Out");

           }
        }

      if(USEMOVETOBREAKEVEN)
        {MOVETOBREAKEVEN();}
      Trail1();
      ticket=0;
     
      if(Bars<100)
        {
         Print("bars less than 100");
         return;
        }
      if(Take_Profit<10)
        {
         Print("TakeProfit less than 10");
         return;
        }
      HideTestIndicators(true);
      double  MA_1_t=iMA(NULL,L,FastMA,0,MODE_LWMA,PRICE_TYPICAL,0); // МА_1
      double MA_2_t=iMA(NULL,L,SlowMA,0,MODE_LWMA,PRICE_TYPICAL,0); // МА_2   
      double   MomLevel=MathAbs(100-iMomentum(NULL,T,14,PRICE_CLOSE,1));
      double   MomLevel1=MathAbs(100 - iMomentum(NULL,T,14,PRICE_CLOSE,2));
      double   MomLevel2=MathAbs(100 - iMomentum(NULL,T,14,PRICE_CLOSE,3));
   double  MacdMAIN0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double  MacdSIGNAL0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);
   HideTestIndicators(false);

      // if(getOpenOrders()==0)
double  LOT = Lots * MathPow(LotExponent, CountTrades());

      //--- no opened orders identified
      if(AccountFreeMargin()<(1000*Lots))
        {
         Print("We have no money. Free Margin = ",AccountFreeMargin());
         return;
        }
      if(CountTrades()<Max_Trades)
         if(MABOUNCE1()==1)
            if(MA_1_t>MA_2_t)
               if(MomLevel<Mom_Buy || MomLevel1<Mom_Buy || MomLevel2<Mom_Buy)
               if((MacdMAIN0>0 && MacdMAIN0>MacdSIGNAL0) || (MacdMAIN0<0 && MacdMAIN0>MacdSIGNAL0)) 
                 {
                  if(NewBarFlag)
                     if((CheckVolumeValue(LotsOptimized(LOT)))==TRUE)
                        if((CheckMoneyForTrade(Symbol(),LotsOptimized(LOT),OP_BUY))==TRUE)
                           if((CheckStopLoss_Takeprofit(OP_BUY,NDTP(Bid-Stop_Loss*pips),NDTP(Bid+Take_Profit*pips)))==TRUE)
                              ticket=OrderSend(Symbol(),OP_BUY,LotsOptimized(LOT),ND(Ask),3,NDTP(Bid-Stop_Loss*pips),NDTP(Bid+Take_Profit*pips),"Long 1",MagicNumber,0,PaleGreen);
                  if(ticket>0)
                    {
                     if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
                        Print("BUY order opened : ",OrderOpenPrice());
                     Alert("we just got a buy signal on the ",_Period,"M",_Symbol);
                     SendNotification("we just got a buy signal on the1 "+(string)_Period+"M"+_Symbol);
                     SendMail("Order sent successfully","we just got a buy signal on the1 "+(string)_Period+"M"+_Symbol);
                    }
                  else
                     Print("Error opening BUY order : ",GetLastError());
                  return;
                 }
      if(CountTrades()<Max_Trades)
         if(MABOUNCE1()==2)
            if(MA_1_t<MA_2_t)
               if(MomLevel<Mom_Sell || MomLevel1<Mom_Sell || MomLevel2<Mom_Sell)
               if((MacdMAIN0>0 && MacdMAIN0<MacdSIGNAL0) || (MacdMAIN0<0 && MacdMAIN0<MacdSIGNAL0))
                 {
                  if(NewBarFlag)
                     if((CheckVolumeValue(LotsOptimized(LOT)))==TRUE)
                        if((CheckMoneyForTrade(Symbol(),LotsOptimized(LOT),OP_SELL))==TRUE)
                           if((CheckStopLoss_Takeprofit(OP_SELL,NDTP(Ask+Stop_Loss*pips),NDTP(Ask-Take_Profit*pips)))==TRUE)
                              ticket=OrderSend(Symbol(),OP_SELL,LotsOptimized(LOT),ND(Bid),3,NDTP(Ask+Stop_Loss*pips),NDTP(Ask-Take_Profit*pips),"Short 1",MagicNumber,0,Red);
                  if(ticket>0)
                    {
                     if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))
                        Print("SELL order opened : ",OrderOpenPrice());
                     Alert("we just got a sell signal on the ",_Period,"M",_Symbol);
                     SendMail("Order sent successfully","we just got a sell signal on the "+(string)_Period+"M"+_Symbol);
                    }
                  else
                     Print("Error opening SELL order : ",GetLastError());
                 }
      //--- exit from the "no opened orders" block
      return;

     }
  }

void Trail1()
  {
   total=OrdersTotal();
//--- it is important to enter the market correctly, but it is more important to exit it correctly...
   for(int cnt=0; cnt<total; cnt++)
     {
      if(!OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderMagicNumber()!=MagicNumber)
         continue;
      if(OrderType()<=OP_SELL &&   // check for opened position
         OrderSymbol()==Symbol())  // check for symbol
        {
         //--- long position is opened
         if(OrderType()==OP_BUY)
           {

            //--- check for trailing stop
            if(TrailingStop>0)
              {
               if(Bid-OrderOpenPrice()>pips*TrailingStop)
                 {
                  if(OrderStopLoss()<Bid-pips*TrailingStop)
                    {

                     RefreshRates();
                     stoploss=Bid-(pips*TrailingStop);
                     takeprofit=OrderTakeProfit();
                     double StopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
                     if(stoploss<StopLevel*pips)
                        stoploss=StopLevel*pips;
                     string symbol=OrderSymbol();
                     double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
                     if(MathAbs(OrderStopLoss()-stoploss)>point)
                        if((pips*TrailingStop)>(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*pips)

                           //--- modify order and exit
                           if(CheckStopLoss_Takeprofit(OP_BUY,stoploss,takeprofit))
                              if(OrderModifyCheck(OrderTicket(),OrderOpenPrice(),stoploss,takeprofit))
                                 if(!OrderModify(OrderTicket(),OrderOpenPrice(),stoploss,takeprofit,0,Green))
                                    Print("OrderModify error ",GetLastError());
                     return;
                    }
                 }
              }
           }
         else // go to short position
           {
            //--- check for trailing stop
            if(TrailingStop>0)
              {
               if((OrderOpenPrice()-Ask)>(pips*TrailingStop))
                 {
                  if((OrderStopLoss()>(Ask+pips*TrailingStop)) || (OrderStopLoss()==0))
                    {

                     RefreshRates();
                     stoploss=Ask+(pips*TrailingStop);
                     takeprofit=OrderTakeProfit();
                     double StopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
                     if(stoploss<StopLevel*pips)
                        stoploss=StopLevel*pips;
                     if(takeprofit<StopLevel*pips)
                        takeprofit=StopLevel*pips;
                     string symbol=OrderSymbol();
                     double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
                     if(MathAbs(OrderStopLoss()-stoploss)>point)
                        if((pips*TrailingStop)>(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*pips)

                           //--- modify order and exit
                           if(CheckStopLoss_Takeprofit(OP_SELL,stoploss,takeprofit))
                              if(OrderModifyCheck(OrderTicket(),OrderOpenPrice(),stoploss,takeprofit))
                                 if(!OrderModify(OrderTicket(),OrderOpenPrice(),stoploss,takeprofit,0,Red))
                                    Print("OrderModify error ",GetLastError());
                     return;
                    }
                 }
              }
           }
        }
     }
  }
void MOVETOBREAKEVEN()

  {
   for(int b=OrdersTotal()-1; b>=0; b--)
     {
      if(OrderSelect(b,SELECT_BY_POS,MODE_TRADES))
         if(OrderMagicNumber()!=MagicNumber)
            continue;
      if(OrderSymbol()==Symbol())
         if(OrderType()==OP_BUY)
            if(Bid-OrderOpenPrice()>WHENTOMOVETOBE*pips)
               if(OrderOpenPrice()>OrderStopLoss())
                  if(CheckStopLoss_Takeprofit(OP_SELL,OrderOpenPrice()+(PIPSTOMOVESL*pips),OrderTakeProfit()))
                     if(OrderModifyCheck(OrderTicket(),OrderOpenPrice(),OrderOpenPrice()+(PIPSTOMOVESL*pips),OrderTakeProfit()))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice()+(PIPSTOMOVESL*pips),OrderTakeProfit(),0,CLR_NONE))
                           Print("eror");
     }

   for(int s=OrdersTotal()-1; s>=0; s--)
     {
      if(OrderSelect(s,SELECT_BY_POS,MODE_TRADES))
         if(OrderMagicNumber()!=MagicNumber)
            continue;
      if(OrderSymbol()==Symbol())
         if(OrderType()==OP_SELL)
            if(OrderOpenPrice()-Ask>WHENTOMOVETOBE*pips)
               if(OrderOpenPrice()<OrderStopLoss())
                  if(CheckStopLoss_Takeprofit(OP_SELL,OrderOpenPrice()-(PIPSTOMOVESL*pips),OrderTakeProfit()))
                     if(OrderModifyCheck(OrderTicket(),OrderOpenPrice(),OrderOpenPrice()-(PIPSTOMOVESL*pips),OrderTakeProfit()))
                        if(!OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice()-(PIPSTOMOVESL*pips),OrderTakeProfit(),0,CLR_NONE))
                           Print("eror");
     }
  }
//--------------------------------------------------------------------------------------

//+------------------------------------------------------------------+
double NDTP(double val)
  {
   RefreshRates();
   double SPREAD=MarketInfo(Symbol(),MODE_SPREAD);
   double StopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL);
   if(val<StopLevel*pips+SPREAD*pips)
      val=StopLevel*pips+SPREAD*pips;
   return(NormalizeDouble(val, Digits));
// return(val);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
double ND(double val)
  {
   return(NormalizeDouble(val, Digits));
  }
//+------------------------------------------------------------------+
//| Checking the new values of levels before order modification      |
//+------------------------------------------------------------------+
bool OrderModifyCheck(int ticket,double price,double sl,double tp)
  {
//--- select order by ticket
   if(OrderSelect(ticket,SELECT_BY_TICKET))
     {
      //--- point size and name of the symbol, for which a pending order was placed
      string symbol=OrderSymbol();
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      //--- check if there are changes in the Open price
      bool PriceOpenChanged=true;
      int type=OrderType();
      if(!(type==OP_BUY || type==OP_SELL))
        {
         PriceOpenChanged=(MathAbs(OrderOpenPrice()-price)>point);
        }
      //--- check if there are changes in the StopLoss level
      bool StopLossChanged=(MathAbs(OrderStopLoss()-sl)>point);
      //--- check if there are changes in the Takeprofit level
      bool TakeProfitChanged=(MathAbs(OrderTakeProfit()-tp)>point);
      //--- if there are any changes in levels
      if(PriceOpenChanged || StopLossChanged || TakeProfitChanged)
         return(true);  // order can be modified
      //--- there are no changes in the Open, StopLoss and Takeprofit levels
      else
         //--- notify about the error
         PrintFormat("Order #%d already has levels of Open=%.5f SL=%.5f TP=%.5f",
                     ticket,OrderOpenPrice(),OrderStopLoss(),OrderTakeProfit());
     }
//--- came to the end, no changes for the order
   return(false);       // no point in modifying
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool CheckStopLoss_Takeprofit(ENUM_ORDER_TYPE type,double SL,double TP)
  {
//--- get the SYMBOL_TRADE_STOPS_LEVEL level
   int stops_level=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(stops_level!=0)
     {
      PrintFormat("SYMBOL_TRADE_STOPS_LEVEL=%d: StopLoss and TakeProfit must"+
                  " not be nearer than %d points from the closing price",stops_level,stops_level);
     }
//---
   bool SL_check=false,TP_check=false;
//--- check only two order types
   switch(type)
     {
      //--- Buy operation
      case  ORDER_TYPE_BUY:
        {
         //--- check the StopLoss
         SL_check=(Bid-SL>stops_level*_Point);
         if(!SL_check)
            PrintFormat("For order %s StopLoss=%.5f must be less than %.5f"+
                        " (Bid=%.5f - SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),SL,Bid-stops_level*_Point,Bid,stops_level);
         //--- check the TakeProfit
         TP_check=(TP-Bid>stops_level*_Point);
         if(!TP_check)
            PrintFormat("For order %s TakeProfit=%.5f must be greater than %.5f"+
                        " (Bid=%.5f + SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),TP,Bid+stops_level*_Point,Bid,stops_level);
         //--- return the result of checking
         return(SL_check&&TP_check);
        }
      //--- Sell operation
      case  ORDER_TYPE_SELL:
        {
         //--- check the StopLoss
         SL_check=(SL-Ask>stops_level*_Point);
         if(!SL_check)
            PrintFormat("For order %s StopLoss=%.5f must be greater than %.5f "+
                        " (Ask=%.5f + SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),SL,Ask+stops_level*_Point,Ask,stops_level);
         //--- check the TakeProfit
         TP_check=(Ask-TP>stops_level*_Point);
         if(!TP_check)
            PrintFormat("For order %s TakeProfit=%.5f must be less than %.5f "+
                        " (Ask=%.5f - SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),TP,Ask-stops_level*_Point,Ask,stops_level);
         //--- return the result of checking
         return(TP_check&&SL_check);
        }
      break;
     }
//--- a slightly different function is required for pending orders
   return false;
  }
int getOpenOrders()
  {

   int Orders=0;
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false)
        {
         continue;
        }
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber)
        {
         continue;
        }
      Orders++;
     }
   return(Orders);
  }
double LotsOptimized1Mxs(double llots)
  {
   double lots=llots;
//--- minimal allowed volume for trade operations
   double minlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(lots<minlot)
     { lots=minlot; }
//--- maximal allowed volume of trade operations
   double maxlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(lots>maxlot)
     { lots=maxlot;  }
//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   int ratio=(int)MathRound(lots/volume_step);
   if(MathAbs(ratio*volume_step-lots)>0.0000001)
     {  lots=ratio*volume_step;}
   if(((AccountStopoutMode()==1) &&
       (AccountFreeMarginCheck(Symbol(),OP_BUY,lots)>AccountStopoutLevel()))
      || ((AccountStopoutMode()==0) &&
          ((AccountEquity()/(AccountEquity()-AccountFreeMarginCheck(Symbol(),OP_BUY,lots))*100)>AccountStopoutLevel())))
      return(lots);
   /* else  Print("StopOut level  Not enough money for ",OP_SELL," ",lot," ",Symbol());*/
   return(0);
  }
double LotsOptimizedMxs(double llots)
  {
   double lots=llots;
//--- minimal allowed volume for trade operations
   double minlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(lots<minlot)
     {
      lots=minlot;
      Print("Volume is less than the minimal allowed ,we use",minlot);
     }
//--- maximal allowed volume of trade operations
   double maxlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(lots>maxlot)
     {
      lots=maxlot;
      Print("Volume is greater than the maximal allowed,we use",maxlot);
     }
//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   int ratio=(int)MathRound(lots/volume_step);
   if(MathAbs(ratio*volume_step-lots)>0.0000001)
     {
      lots=ratio*volume_step;

      Print("Volume is not a multiple of the minimal step ,we use the closest correct volume ",ratio*volume_step);
     }

   return(lots);

  }
bool CheckVolumeValue(double volume/*,string &description*/)

  {
   double lot=volume;
   int    orders=OrdersHistoryTotal();     // history orders total
   int    losses=0;                  // number of losses orders without a break
//--- select lot size
//--- maximal allowed volume of trade operations
   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(lot>max_volume)

      Print("Volume is greater than the maximal allowed ,we use",max_volume);
//  return(false);

//--- minimal allowed volume for trade operations
   double minlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(lot<minlot)

      Print("Volume is less than the minimal allowed ,we use",minlot);
//  return(false);

//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   int ratio=(int)MathRound(lot/volume_step);
   if(MathAbs(ratio*volume_step-lot)>0.0000001)
     {
      Print("Volume is not a multiple of the minimal step ,we use, the closest correct volume is %.2f",
            volume_step,ratio*volume_step);
      //   return(false);
     }
//  description="Correct volume value";
   return(true);
  }
bool CheckMoneyForTrade(string symb,double lots,int type)
  {
   double free_margin=AccountFreeMarginCheck(symb,type,lots);
//-- if there is not enough money
   if(free_margin>0)
     {
      if((AccountStopoutMode()==1) &&
         (AccountFreeMarginCheck(symb,type,lots)<AccountStopoutLevel()))
        {
         Print("StopOut level  Not enough money ", type," ",lots," ",Symbol());
         return(false);
        }
      if(AccountEquity()-AccountFreeMarginCheck(Symbol(),type,lots)==0)
        {
         Print("StopOut level  Not enough money ", type," ",lots," ",Symbol());
         return(false);
        }
      if((AccountStopoutMode()==0) &&
         ((AccountEquity()/(AccountEquity()-AccountFreeMarginCheck(Symbol(),type,lots))*100)<AccountStopoutLevel()))
        {
         Print("StopOut level  Not enough money ", type," ",lots," ",Symbol());
         return(false);
        }
     }
   else
      if(free_margin<0)
        {
         string oper=(type==OP_BUY)? "Buy":"Sell";
         Print("Not enough money for ",oper," ",lots," ",symb," Error code=",GetLastError());
         return(false);
        }
//--- checking successful
   return(true);
  }
int CountTrades()
  {
   int count=0;
   for(int trade=OrdersTotal()-1; trade>=0; trade--)
     {
      if(!OrderSelect(trade,SELECT_BY_POS,MODE_TRADES))
         Print("Error");
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber)
         continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
         if(OrderType()==OP_SELL || OrderType()==OP_BUY)
            count++;
     }
   return (count);
  }
double AccountEquityHigh()
  {
   if(CountTrades()==0)
      AccountEquityHighAmt=AccountEquity();
   if(AccountEquityHighAmt<PrevEquity)
      AccountEquityHighAmt=PrevEquity;
   else
      AccountEquityHighAmt=AccountEquity();
   PrevEquity=AccountEquity();
   return (AccountEquityHighAmt);
  }
double CalculateProfit()
  {
   double Profit=0;
   for(int cnt=OrdersTotal()-1; cnt>=0; cnt--)
     {
      if(!OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES))
         Print("Error");
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber)
         continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
         if(OrderType()==OP_BUY || OrderType()==OP_SELL)
            Profit+=OrderProfit();
     }
   return (Profit);
  }
void CloseThisSymbolAll()
  {
   double CurrentPairProfit=CalculateProfit();
   for(int trade=OrdersTotal()-1; trade>=0; trade--)
     {
      if(!OrderSelect(trade,SELECT_BY_POS,MODE_TRADES))
         Print("Error");
      if(OrderSymbol()==Symbol())
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
           {
            if(OrderType() == OP_BUY)
               if(!OrderClose(OrderTicket(), OrderLots(), Bid, 3, Blue))
                  Print("Error");
            if(OrderType() == OP_SELL)
               if(!OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red))
                  Print("Error");
           }
         Sleep(1000);
         if(UseEquityStop)
           {
            if(CurrentPairProfit>0.0 && MathAbs(CurrentPairProfit)>TotalEquityRisk/100.0*AccountEquityHigh())
              {
               return;

              }
           }

        }
     }
  }
double LotsOptimized(double llots)
  {
   double lot=llots;
   int    orders=OrdersHistoryTotal();     // history orders total
   int    losses=0;                  // number of losses orders without a break
//--- calcuulate number of losses orders without a break
   if(IncreaseFactor>0)
     {
      for(int i=orders-1; i>=0; i--)
        {
         if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)==false)
           {
            Print("Error in history!");
            break;
           }
         if(OrderSymbol()!=Symbol())
            continue;
         //---
         if(OrderProfit()>0)
            break;
         if(OrderProfit()<0)
            losses++;
        }
      if(losses>1)
         // lot=NormalizeDouble(lot+lot*losses/IncreaseFactor,1);
         lot=AccountFreeMargin()*IncreaseFactor/1000.0;
     }
//--- minimal allowed volume for trade operations
   double minlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(lot<minlot)
     {
      lot=minlot;
      Print("Volume is less than the minimal allowed ,we use",minlot);
     }
// lot=minlot;

//--- maximal allowed volume of trade operations
   double maxlot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(lot>maxlot)
     {
      lot=maxlot;
      Print("Volume is greater than the maximal allowed,we use",maxlot);
     }
// lot=maxlot;

//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   int ratio=(int)MathRound(lot/volume_step);
   if(MathAbs(ratio*volume_step-lot)>0.0000001)
     {
      lot=ratio*volume_step;

      Print("Volume is not a multiple of the minimal step ,we use the closest correct volume ",ratio*volume_step);
     }
   return(lot);

  }
int MABOUNCE1()
  {
   int MAVALUE=0;


   for(int i=5; i<100; i++)
     {

      double FASTMA=iMA(NULL,T,i,0,MODE_LWMA,PRICE_TYPICAL,0);
      double SLOWMA=iMA(NULL,T,200,0,MODE_LWMA,PRICE_TYPICAL,0);

      if(FASTMA>SLOWMA && iLow(Symbol(),T,1)<=FASTMA && iOpen(Symbol(),T,1)>FASTMA)
        {
         return(1);

         Comment("The trend is up");
        }

      if(FASTMA<SLOWMA && iHigh(Symbol(),T,1)>=FASTMA && iOpen(Symbol(),T,1)<FASTMA)
        {
         return(2);

         Comment("The trend is down");
        }
     }

   return(0);
  }
void Take_Profit_In_Money()
  {
   if((TP_In_Money != 0))
     {
      PROFIT_SUM1 = 0;
      for(int i=OrdersTotal(); i>0; i--)
        {
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
           {
            if(OrderSymbol()==Symbol())
              {
               if(OrderType() == OP_BUY || OrderType() == OP_SELL)
                 {
                  PROFIT_SUM1 = (PROFIT_SUM1 + OrderProfit());
                 }}}}
      if((PROFIT_SUM1 >= TP_In_Money))
        {
         RemoveAllOrders();
        }
     }
  }
//------------------------------------------------ TP_In_Percent -------------------------------------------------
double Take_Profit_In_percent()
  {
   if((TP_In_Percent != 0))
     {
      double TP_Percent = ((TP_In_Percent * AccountBalance()) / 100);
      double  PROFIT_SUM = 0;
      for(int i=OrdersTotal(); i>0; i--)
        {
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
           {
            if(OrderSymbol()==Symbol())
              {
               if(OrderType() == OP_BUY || OrderType() == OP_SELL)
                 {
                  PROFIT_SUM = (PROFIT_SUM + OrderProfit());
                 }
              }
           }
         if(PROFIT_SUM >= TP_Percent)
           {
            RemoveAllOrders();
           }
        }

     }
   return(0);
  }

void RemoveAllOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0 ; i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS))
         Print("ERROR");
      if(OrderSymbol() != Symbol())
         continue;
      double price = MarketInfo(OrderSymbol(),MODE_ASK);
      if(OrderType() == OP_BUY)
         price = MarketInfo(OrderSymbol(),MODE_BID);
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
        {
         if(!OrderClose(OrderTicket(), OrderLots(),price,5))
            Print("ERROR");
        }
      else
        {
         if(!OrderDelete(OrderTicket()))
            Print("ERROR");
        }
      Sleep(100);
      int error = GetLastError();
      // if(error > 0)
      // Print("Unanticipated error: ", ErrorDescription(error));
      RefreshRates();
     }
  }

int TRAIL_PROFIT_IN_MONEY2()
  {
// double TP_Percent = ((TP_In_Money * AccountBalance()) / 100);
// double SL_Percent = ((SL_In_Money * AccountBalance()) / 100);
   PROFIT_SUM1 = 0;
   PROFIT_SUM2 = 0;
   INDEX2 = 0;
   double PROFIT_SUM3 = 0;
   for(int j=OrdersTotal(); j>0; j--)
     {if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES))
        {if(OrderSymbol()==Symbol())
           { if(OrderType() == OP_BUY || OrderType() == OP_SELL)
              { PROFIT_SUM1  = PROFIT_SUM1 + (OrderProfit() + OrderCommission() + OrderSwap());
               // Print("PROFIT_SUM1",PROFIT_SUM1);
              } }  }  }
   if(PROFIT_SUM1>= Take_Profit_Money)
      // Print("PROFIT_SUM1",PROFIT_SUM1);
     {for(int i=OrdersTotal(); i>0; i--)
        { if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
           { if(OrderSymbol()==Symbol())
              {if(OrderType() == OP_BUY || OrderType() == OP_SELL)
                 {
                  PROFIT_SUM2  = PROFIT_SUM2 + (OrderProfit() + OrderCommission() + OrderSwap());
                 }
               if(PROFIT_SUM1>= PROFIT_SUM3)
                 {PROFIT_SUM3=PROFIT_SUM1;}
               if(PROFIT_SUM2<=PROFIT_SUM3-Stop_Loss_Money)
                  RemoveAllOrders();
              }
           }
        }

     }
// if(PROFIT_SUM2<=SL_In_Money)
//  RemoveAllOrders();
   return(0);
  }

int Close_BUY()
  {
//-------------------------------------------------------------------------------------------------
   double  MacdMAIN0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double  MacdSIGNAL0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);
//+------------------------------------------------------------------------------------------------+  
   int count_0 = 0;
   for(int pos_4 = OrdersTotal() - 1; pos_4 >= 0; pos_4--)
     {
      bool   cg = OrderSelect(pos_4, SELECT_BY_POS, MODE_TRADES);
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderSymbol() == Symbol())
         if(OrderType() == OP_BUY)
            if((MacdMAIN0>0 && MacdMAIN0<MacdSIGNAL0) || (MacdMAIN0<0 && MacdMAIN0<MacdSIGNAL0))
               Close_All_Buy_Trades();

     }
   return (count_0);
  }
int Close_SELL()
  {
   double  MacdMAIN0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double  MacdSIGNAL0=iMACD(NULL,PERIOD_MN1,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);   
   int count_0 = 0;
   for(int pos_4 = OrdersTotal() - 1; pos_4 >= 0; pos_4--)
     {
      bool   cg = OrderSelect(pos_4, SELECT_BY_POS, MODE_TRADES);
      if(OrderSymbol() != Symbol() )
         continue;
      if(OrderSymbol() == Symbol())
         if(OrderType() == OP_SELL)
             if((MacdMAIN0>0 && MacdMAIN0>MacdSIGNAL0) || (MacdMAIN0<0 && MacdMAIN0>MacdSIGNAL0)) 
               Close_All_Sell_Trades();
     }
   return (count_0);
  }

void Close_All_Buy_Trades()
  {
   double CurrentPairProfit=CalculateProfit();
   for(int trade=OrdersTotal()-1; trade>=0; trade--)
     {
      if(!OrderSelect(trade,SELECT_BY_POS,MODE_TRADES))
         Print("Error");
      if(OrderSymbol()==Symbol())
        {
         if(OrderSymbol()==Symbol() )
           {
            if(OrderType() == OP_BUY)
               if(!OrderClose(OrderTicket(), OrderLots(), Bid, 3, Blue))
                  Print("Error");
              if(OrderType() == OP_SELL)
                if(!OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red))
               Print("Error");
           }
         Sleep(1000);

        }
     }
  }

void Close_All_Sell_Trades()
  {
   double CurrentPairProfit=CalculateProfit();
   for(int trade=OrdersTotal()-1; trade>=0; trade--)
     {
      if(!OrderSelect(trade,SELECT_BY_POS,MODE_TRADES))
         Print("Error");
      if(OrderSymbol()==Symbol())
        {
         if(OrderSymbol()==Symbol())
           {
             if(OrderType() == OP_BUY)
             if(!OrderClose(OrderTicket(), OrderLots(), Bid, 3, Blue))
                Print("Error");
            if(OrderType() == OP_SELL)
               if(!OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red))
                  Print("Error") }
         Sleep(1000);
        } }}