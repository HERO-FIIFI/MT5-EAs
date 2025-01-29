// Expert Advisor parameters
input double InitialRiskPercent = 1.0;     // Initial risk per trade (1%)
input double IncreasedRiskPercent = 2.0;   // Risk after 25% profit (2%)
input double MinimumStopDistance = 0.0001; // Minimum distance for stop loss

// Declare variables
double initial_balance;
double current_risk_percent;
string symbols[] = {"EURUSD", "GBPUSD", "GBPJPY", "NZDUSD"};
ENUM_TIMEFRAMES timeframe = PERIOD_H4;
datetime lastTradeTime;

//Initialization function
void OnInit()
{
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("Initial balance: ", initial_balance);
    current_risk_percent = InitialRiskPercent;
    lastTradeTime = TimeCurrent();
}

// Get point value for the symbol
double GetPointValue(string symbol)
{
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(tickSize <= 0 || point <= 0)
    {
        Print("Error: Invalid tick size or point value for ", symbol);
        return 0;
    }
    
    // For 5-digit brokers
    if(point == 0.00001 || point == 0.001)
    {
        return tickValue * (tickSize / point);
    }
    
    return tickValue;
}

// Calculate lot size based on risk percentage
double CalculateLotSize(string symbol, double riskAmount, double stopLoss, double entryPrice)
{
    // Initial safety checks
    if(riskAmount <= 0)
    {
        Print("Error: Risk amount must be greater than 0");
        return 0;
    }
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    if(stopDistance < MinimumStopDistance)
    {
        Print("Error: Stop distance too small for ", symbol);
        return 0;
    }
    
    // Get symbol point and digits
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    if(point <= 0)
    {
        Print("Error: Invalid point value for ", symbol);
        return 0;
    }
    
    // Calculate points between entry and stop loss
    double points = stopDistance / point;
    
    // Get point value
    double pointValue = GetPointValue(symbol);
    if(pointValue <= 0)
    {
        Print("Error: Invalid point value calculation for ", symbol);
        return 0;
    }
    
    // Calculate lot size with safety check
    double lotSize = 0;
    if(points * pointValue != 0)
    {
        lotSize = riskAmount / (points * pointValue);
    }
    else
    {
        Print("Error: Invalid calculation values for lot size");
        return 0;
    }
    
    // Normalize lot size to broker's requirements
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if(lotStep <= 0)
    {
        Print("Error: Invalid lot step for ", symbol);
        return minLot;
    }
    
    // Round to the nearest lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Ensure lot size is within limits
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Final validation
    if(lotSize <= 0)
    {
        Print("Warning: Calculated lot size is 0 or negative for ", symbol);
        return minLot;
    }
    
    return lotSize;
}

// Expert Advisor tick function
void OnTick()
{
    for(int i = 0; i < ArraySize(symbols); i++)
    {
        // Skip if not enough time has passed since last trade
        if(TimeCurrent() - lastTradeTime < 300) // 5 minutes
            continue;
            
        MqlRates rates[];
        int copied = CopyRates(symbols[i], timeframe, 0, 100, rates);
        if(copied < 0)
        {
            Print("Failed to retrieve market data for ", symbols[i]);
            continue;
        }

        double high = iHigh(symbols[i], timeframe, 0);
        double low = iLow(symbols[i], timeframe, 0);
        double diff = high - low;
        
        if(diff < MinimumStopDistance)
        {
            Print("Warning: Price range too small for ", symbols[i]);
            continue;
        }

        double fibLevels[];
        ArrayResize(fibLevels, 6);
        fibLevels[0] = high - 0.236 * diff;
        fibLevels[1] = high - 0.382 * diff;
        fibLevels[2] = high - 0.500 * diff;
        fibLevels[3] = high - 0.618 * diff;
        fibLevels[4] = high - 0.786 * diff;
        fibLevels[5] = high - 0.750 * diff;

        bool uptrend = rates[0].low > rates[1].low && rates[0].high > rates[1].high;
        bool downtrend = rates[0].low < rates[1].low && rates[0].high < rates[1].high;

        double sl, tp;
        double entry_price = SymbolInfoDouble(symbols[i], SYMBOL_ASK);
        
        if(entry_price <= 0)
        {
            Print("Error: Invalid entry price for ", symbols[i]);
            continue;
        }

        // Calculate risk amount
        double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(account_balance <= 0)
        {
            Print("Error: Invalid account balance");
            continue;
        }
        
        double risk_amount = account_balance * (current_risk_percent / 100.0);

        // Trading logic
        if(uptrend && rates[0].close <= fibLevels[5])
        {
            sl = low;
            tp = high;

            if(MathAbs(tp - sl) < MinimumStopDistance)
            {
                Print("Warning: Stop loss distance too small for ", symbols[i]);
                continue;
            }

            double lot_size = CalculateLotSize(symbols[i], risk_amount, sl, entry_price);
            if(lot_size <= 0)
            {
                Print("Error: Invalid lot size calculated for ", symbols[i]);
                continue;
            }

            MqlTradeRequest request = {};
            request.action = TRADE_ACTION_DEAL;  // Changed to market order
            request.symbol = symbols[i];
            request.volume = lot_size;
            request.price = entry_price;
            request.sl = sl;
            request.tp = tp;
            request.deviation = 20;
            request.type = ORDER_TYPE_BUY;
            request.type_filling = ORDER_FILLING_FOK;

            MqlTradeResult result = {};
            if(!OrderSend(request, result))
            {
                Print("Order send failed for ", symbols[i], ". Error code: ", GetLastError());
            }
            else
            {
                Print("Order placed: Buy ", lot_size, " lots of ", symbols[i], " at ", entry_price);
                lastTradeTime = TimeCurrent();
            }
        }
        else if(downtrend && rates[0].close >= fibLevels[5])
        {
            sl = high;
            tp = low;

            if(MathAbs(tp - sl) < MinimumStopDistance)
            {
                Print("Warning: Stop loss distance too small for ", symbols[i]);
                continue;
            }

            double lot_size = CalculateLotSize(symbols[i], risk_amount, sl, entry_price);
            if(lot_size <= 0)
            {
                Print("Error: Invalid lot size calculated for ", symbols[i]);
                continue;
            }

            MqlTradeRequest request = {};
            request.action = TRADE_ACTION_DEAL;  // Changed to market order
            request.symbol = symbols[i];
            request.volume = lot_size;
            request.price = entry_price;
            request.sl = sl;
            request.tp = tp;
            request.deviation = 20;
            request.type = ORDER_TYPE_SELL;
            request.type_filling = ORDER_FILLING_FOK;

            MqlTradeResult result = {};
            if(!OrderSend(request, result))
            {
                Print("Order send failed for ", symbols[i], ". Error code: ", GetLastError());
            }
            else
            {
                Print("Order placed: Sell ", lot_size, " lots of ", symbols[i], " at ", entry_price);
                lastTradeTime = TimeCurrent();
            }
        }
    }

    // Update risk management if in profit
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(current_balance >= initial_balance * 1.25 && current_risk_percent != IncreasedRiskPercent)
    {
        current_risk_percent = IncreasedRiskPercent;
        Print("Account balance increased by 25%. Adjusting risk to ", IncreasedRiskPercent, "%");
    }
}

void OnDeinit(const int reason)
{
    Print("Expert Advisor deactivated. Reason: ", reason);
}
//losses massively