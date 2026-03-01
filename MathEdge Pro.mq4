//+------------------------------------------------------------------+
//|                                                    MathEdge Pro  |
//|                           MathEdge Pro - MT4 EA (MQL4)           |
//|                                                                  |
//|  Version: 1.1 (2026-03-01)                                       |
//|  Expiry:  2026-03-28 (New York time)                             |
//|                                                                  |
//|  Changelog:                                                      |
//|  v1.1 - Extended expiry to 2026-03-28                            |
//|       - Added on-chart dashboard (account, bias, levels, expiry) |
//|       - Improved spread filter logging                           |
//|       - Added day-of-week filter (skip weekends/holidays)        |
//|       - Improved comment clarity and code structure              |
//|  v1.0 - Initial release with MathEdge Pro strategy               |
//|       - Custom NY-day OHLC from M1 bars                          |
//|       - Three-tier pending order system (T1/T2/T3)               |
//|       - DST-aware NY time conversion                             |
//+------------------------------------------------------------------+
#property strict

//---------------------- Inputs -------------------------------------
input int    MagicNumber              = 260128;       // Unique magic for this EA
input double Lots                     = 0.10;         // Fixed lot size
input bool   UseRiskPercent           = false;        // Use % risk instead of fixed lots
input double RiskPercent              = 1.0;          // % of free margin per trade
input int    MaxSpreadPoints          = 300;          // Max spread allowed (points)
input int    Slippage                 = 5;            // Slippage (points)

input bool   UseSymbolWhitelist       = true;         // Restrict to indices symbols
input string AllowedSymbolsCSV        = "US30,NAS100,NDQ,DJI,US30.cash,NAS100.cash,US30m,NAS100m"; // Comma-separated

input bool   UseCustomNYDailyOHLC     = true;         // Build NY-day OHLC from M1 bars
input int    NYDayStartHour           = 18;           // NY session day start hour
input int    NYDayStartMinute         = 0;            // NY session day start minute
input int    TradingEndHour           = 15;           // NY trading end hour
input int    TradingEndMinute         = 29;           // NY trading end minute

input bool   PlacePendingOrders       = true;         // Place pendings for "touch=execution"
input bool   CancelPendingsAfterWindow = true;        // Cancel pendings outside window
input bool   CloseOpenAtWindowEnd     = false;        // Close open trades at window end
input int    EmergencySL_Points       = 0;            // 0=disabled; hard SL in points

input bool   DrawLevels               = true;         // Draw PRV/CV/H/L/TP lines on chart
input bool   ShowDashboard            = true;         // Show on-chart info dashboard

//---------------------- Expiry -------------------------------------
string ExpiryNYDate            = "2026.03.28";  // Expiry date in New York time (YYYY.MM.DD)
input bool   ExpiryCloseOpenTrades   = false;         // Close open trades when expired

//---------------------- Globals ------------------------------------
int      g_sessionKey = 0;        // YYYYMMDD of NY session start date (18:00)
datetime g_sessionStartUTC = 0;   // UTC timestamp of NY 18:00 for current session
bool     g_levelsReady = false;

double g_O = 0, g_H = 0, g_L = 0, g_CV = 0, g_PRV = 0, g_Net = 0, g_TP = 0;
int    g_bias = 0;               // 1=BUY only, -1=SELL only, 0=no trade

bool   g_activationFilled = false;
int    g_t1 = -1, g_t2 = -1, g_t3 = -1;

//---------------------- Helpers: string ----------------------------
string Trim(string s)
  {
   while(StringLen(s) > 0 && (StringGetChar(s, 0) == ' ' || StringGetChar(s, 0) == '\t' || StringGetChar(s, 0) == '\r' || StringGetChar(s, 0) == '\n'))
      s = StringSubstr(s, 1);
   while(StringLen(s) > 0)
     {
      int last = StringLen(s) - 1;
      int c = StringGetChar(s, last);
      if(c == ' ' || c == '\t' || c == '\r' || c == '\n')
         s = StringSubstr(s, 0, last);
      else
         break;
     }
   return s;
  }

// MQL4 doesn't have StringUpper() (that's MQL5). This helper is safe for ASCII.
string StrUpper(string s)
  {
   uchar arr[];
   int n = StringToCharArray(s, arr, 0, -1);
   if(n <= 0)
      return s;
   for(int i = 0; i < n; i++)
     {
      if(arr[i] >= 97 && arr[i] <= 122)
         arr[i] = (uchar)(arr[i] - 32);
     }
   int outLen = n;
   if(arr[n - 1] == 0)
      outLen = n - 1;
   return CharArrayToString(arr, 0, outLen);
  }

//+------------------------------------------------------------------+
//| Check if the current symbol is in the allowed whitelist          |
//+------------------------------------------------------------------+
bool SymbolAllowed()
  {
   if(!UseSymbolWhitelist)
      return true;
   string sym = Symbol();
   string list = AllowedSymbolsCSV;
   int n = 0;
   while(true)
     {
      int pos = StringFind(list, ",");
      string token;
      if(pos < 0)
        {
         token = list;
        }
      else
        {
         token = StringSubstr(list, 0, pos);
        }
      token = Trim(token);
      if(token != "")
        {
         string symU = StrUpper(sym);
         string tokU = StrUpper(token);
         if(StringFind(symU, tokU) >= 0)
            return true;
        }
      if(pos < 0)
         break;
      list = StringSubstr(list, pos + 1);
      n++;
      if(n > 200)
         break;
     }
   return false;
  }

//---------------------- Helpers: time/date --------------------------
datetime MakeTime(int y, int mo, int d, int h, int mi, int s)
  {
   string str = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", y, mo, d, h, mi, s);
   return StrToTime(str);
  }

//+------------------------------------------------------------------+
//| Find the first Sunday of a given month                           |
//+------------------------------------------------------------------+
int FirstSundayDOM(int year, int month)
  {
   datetime t = MakeTime(year, month, 1, 0, 0, 0);
   int dow = TimeDayOfWeek(t);
   int offset = (7 - dow) % 7;
   return 1 + offset;
  }

//+------------------------------------------------------------------+
//| DST boundary helpers for US Eastern Time                         |
//+------------------------------------------------------------------+
int SecondSundayMarchDOM(int year) { return FirstSundayDOM(year, 3) + 7; }
int FirstSundayNovemberDOM(int year) { return FirstSundayDOM(year, 11); }

//+------------------------------------------------------------------+
//| Check if a UTC timestamp falls within US DST                     |
//+------------------------------------------------------------------+
bool IsNYDST_UTC(datetime gmt)
  {
   int y = TimeYear(gmt);
   int domStart = SecondSundayMarchDOM(y);
   datetime startUTC = MakeTime(y, 3, domStart, 7, 0, 0);
   int domEnd = FirstSundayNovemberDOM(y);
   datetime endUTC = MakeTime(y, 11, domEnd, 6, 0, 0);
   if(gmt >= startUTC && gmt < endUTC)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Return UTC-to-NY offset in seconds (-4 DST, -5 EST)             |
//+------------------------------------------------------------------+
int NYOffsetSeconds(datetime gmt)
  {
   return (IsNYDST_UTC(gmt) ? -4 * 3600 : -5 * 3600);
  }

datetime ToNY(datetime gmt) { return gmt + NYOffsetSeconds(gmt); }

//+------------------------------------------------------------------+
//| Build NY expiry timestamp (end of ExpiryNYDate at 23:59:59 NY)   |
//+------------------------------------------------------------------+
datetime ExpiryNYTimestamp()
  {
   int y  = (int)StringToInteger(StringSubstr(ExpiryNYDate, 0, 4));
   int mo = (int)StringToInteger(StringSubstr(ExpiryNYDate, 5, 2));
   int d  = (int)StringToInteger(StringSubstr(ExpiryNYDate, 8, 2));
   return MakeTime(y, mo, d, 23, 59, 59);
  }

//+------------------------------------------------------------------+
//| Check if the EA has expired based on current GMT time            |
//+------------------------------------------------------------------+
bool IsExpired(datetime gmtNow)
  {
   datetime nyNow = ToNY(gmtNow);
   datetime nyExp = ExpiryNYTimestamp();
   return (nyNow > nyExp);
  }

//+------------------------------------------------------------------+
//| Calculate how many days remain until expiry                      |
//+------------------------------------------------------------------+
int DaysUntilExpiry(datetime gmtNow)
  {
   datetime nyNow = ToNY(gmtNow);
   datetime nyExp = ExpiryNYTimestamp();
   if(nyNow > nyExp)
      return 0;
   return (int)((nyExp - nyNow) / 86400);
  }

//+------------------------------------------------------------------+
//| Determine the current NY session key (YYYYMMDD)                  |
//+------------------------------------------------------------------+
int CurrentSessionKey(datetime gmtNow)
  {
   datetime nyNow = ToNY(gmtNow);
   int y = TimeYear(nyNow);
   int mo = TimeMonth(nyNow);
   int d  = TimeDay(nyNow);
   int h  = TimeHour(nyNow);
   int mi = TimeMinute(nyNow);
   datetime baseDate = MakeTime(y, mo, d, 0, 0, 0);
   if(h > NYDayStartHour || (h == NYDayStartHour && mi >= NYDayStartMinute))
     {
      // Current time is after session start - use today as base
     }
   else
     {
      // Current time is before session start - roll back to previous day
      baseDate -= 86400;
      y = TimeYear(baseDate);
      mo = TimeMonth(baseDate);
      d = TimeDay(baseDate);
     }
   return y * 10000 + mo * 100 + d;
  }

//+------------------------------------------------------------------+
//| Convert session key back to UTC start time                       |
//+------------------------------------------------------------------+
datetime SessionStartUTCFromKey(int sessionKey)
  {
   int y = sessionKey / 10000;
   int mo = (sessionKey / 100) % 100;
   int d = sessionKey % 100;
   datetime local = MakeTime(y, mo, d, NYDayStartHour, NYDayStartMinute, 0);
   datetime candUTC = local + 5 * 3600;
   int offset = NYOffsetSeconds(candUTC);
   datetime utc = local - offset;
   return utc;
  }

//+------------------------------------------------------------------+
//| Check if current time is within the trading window               |
//+------------------------------------------------------------------+
bool IsWithinTradingWindow(datetime gmtNow)
  {
   datetime ny = ToNY(gmtNow);
   int h = TimeHour(ny);
   int mi = TimeMinute(ny);
   bool afterStart = (h > NYDayStartHour) || (h == NYDayStartHour && mi >= NYDayStartMinute);
   bool beforeEnd  = (h < TradingEndHour) || (h == TradingEndHour && mi <= TradingEndMinute);
   if(afterStart || beforeEnd)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Check if current time is after the trading window end            |
//+------------------------------------------------------------------+
bool IsAfterWindowEnd(datetime gmtNow)
  {
   datetime ny = ToNY(gmtNow);
   int h = TimeHour(ny);
   int mi = TimeMinute(ny);
   bool afterEnd = (h > TradingEndHour) || (h == TradingEndHour && mi > TradingEndMinute);
   bool beforeStart = (h < NYDayStartHour) || (h == NYDayStartHour && mi < NYDayStartMinute);
   return (afterEnd && beforeStart);
  }

//---------------------- Helpers: OHLC builder -----------------------
//+------------------------------------------------------------------+
//| Build OHLC from M1 bars between startUTC and endUTC              |
//+------------------------------------------------------------------+
bool BuildOHLC_M1(datetime startUTC, datetime endUTC, double &o, double &h, double &l, double &c)
  {
   int tf = PERIOD_M1;
   int startShift = iBarShift(Symbol(), tf, startUTC, true);
   int endShift   = iBarShift(Symbol(), tf, endUTC, true);
   if(startShift < 0)
      return false;
   if(endShift < 0)
      endShift = 0;
   int from = startShift;
   int to   = endShift;
   if(from < to)
     {
      int tmp = from;
      from = to;
      to = tmp;
     }
   if(from - to < 1)
      return false;
   o = iOpen(Symbol(), tf, from);
   h = -1e100;
   l =  1e100;
   for(int i = from; i >= to; i--)
     {
      double hi = iHigh(Symbol(), tf, i);
      double lo = iLow(Symbol(), tf, i);
      if(hi > h)
         h = hi;
      if(lo < l)
         l = lo;
     }
   c = iClose(Symbol(), tf, to);
   if(h < -1e90 || l > 1e90)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Load previous day OHLC and calculate math levels                 |
//+------------------------------------------------------------------+
bool LoadDailyLevels()
  {
   datetime end1 = g_sessionStartUTC;
   datetime start1 = end1 - 86400;
   datetime end2 = start1;
   datetime start2 = end2 - 86400;
   double o1 = 0, h1 = 0, l1 = 0, c1 = 0;
   double o2 = 0, h2 = 0, l2 = 0, c2 = 0;
   bool ok1 = false, ok2 = false;

   // Try custom NY-day OHLC built from M1 bars first
   if(UseCustomNYDailyOHLC)
     {
      ok1 = BuildOHLC_M1(start1, end1, o1, h1, l1, c1);
      ok2 = BuildOHLC_M1(start2, end2, o2, h2, l2, c2);
     }

   // Fallback to broker D1 candles if custom OHLC fails
   if(!ok1 || !ok2)
     {
      o1 = iOpen(Symbol(), PERIOD_D1, 1);
      h1 = iHigh(Symbol(), PERIOD_D1, 1);
      l1 = iLow(Symbol(), PERIOD_D1, 1);
      c1 = iClose(Symbol(), PERIOD_D1, 1);
      c2 = iClose(Symbol(), PERIOD_D1, 2);
      ok1 = (o1 != 0 || h1 != 0 || l1 != 0 || c1 != 0);
      ok2 = (c2 != 0);
      if(!ok1 || !ok2)
         return false;
     }

   // Store levels and calculate directional bias
   g_O  = o1;
   g_H  = h1;
   g_L  = l1;
   g_CV = c1;           // Closing Value (yesterday's close)
   g_PRV = c2;          // Previous Reference Value (day-before-yesterday's close)
   g_Net = g_CV - g_PRV; // Net change determines bias
   if(g_Net > 0)
      g_bias = 1;        // Bullish: buy only
   else
      if(g_Net < 0)
         g_bias = -1;    // Bearish: sell only
      else
         g_bias = 0;     // Flat: no trades
   g_TP = g_CV + g_Net;  // Target price = CV + Net
   return true;
  }

//---------------------- Helpers: drawing ----------------------------
//+------------------------------------------------------------------+
//| Draw or update a horizontal line on the chart                    |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr)
  {
   if(!DrawLevels)
      return;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   else
     {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
     }
  }

//+------------------------------------------------------------------+
//| Update all level lines on the chart                              |
//+------------------------------------------------------------------+
void UpdateDrawings()
  {
   if(!DrawLevels)
      return;
   DrawHLine("MEP_PRV", g_PRV, clrOrange);
   DrawHLine("MEP_CV",  g_CV,  clrAqua);
   DrawHLine("MEP_H",   g_H,   clrRed);
   DrawHLine("MEP_L",   g_L,   clrLime);
   DrawHLine("MEP_TP",  g_TP,  clrYellow);
  }

//+------------------------------------------------------------------+
//| Draw on-chart dashboard with EA status info                      |
//+------------------------------------------------------------------+
void UpdateDashboard(datetime gmtNow)
  {
   if(!ShowDashboard)
     {
      Comment("");
      return;
     }

   string biasStr = "FLAT (no trade)";
   if(g_bias == 1)
      biasStr = "BULLISH (BUY only)";
   else if(g_bias == -1)
      biasStr = "BEARISH (SELL only)";

   int daysLeft = DaysUntilExpiry(gmtNow);
   string expiryWarn = "";
   if(daysLeft <= 7)
      expiryWarn = " ⚠ EXPIRING SOON!";

   string windowStr = "CLOSED";
   if(IsWithinTradingWindow(gmtNow))
      windowStr = "OPEN";

   string dash = "";
   dash += "══════════════════════════════════\n";
   dash += "  MathEdge Pro v1.1\n";
   dash += "══════════════════════════════════\n";
   dash += "  Account: " + AccountName() + " (#" + IntegerToString(AccountNumber()) + ")\n";
   dash += "  Balance: " + DoubleToStr(AccountBalance(), 2) + " | Equity: " + DoubleToStr(AccountEquity(), 2) + "\n";
   dash += "  Symbol:  " + Symbol() + " | Spread: " + IntegerToString(CurrentSpreadPoints()) + " pts\n";
   dash += "──────────────────────────────────\n";
   dash += "  Bias:    " + biasStr + "\n";
   dash += "  Window:  " + windowStr + "\n";
   dash += "  PRV: " + DoubleToStr(g_PRV, Digits) + " | CV:  " + DoubleToStr(g_CV, Digits) + "\n";
   dash += "  High: " + DoubleToStr(g_H, Digits) + " | Low: " + DoubleToStr(g_L, Digits) + "\n";
   dash += "  TP:  " + DoubleToStr(g_TP, Digits) + " | Net: " + DoubleToStr(g_Net, Digits) + "\n";
   dash += "──────────────────────────────────\n";
   dash += "  T1: " + (HasAnyWithTag("MEP T1") ? "PLACED" : "waiting") + "\n";
   dash += "  T2: " + (HasAnyWithTag("MEP T2") ? "PLACED" : (g_activationFilled ? "waiting" : "needs T1 fill")) + "\n";
   dash += "  T3: " + (HasAnyWithTag("MEP T3") ? "PLACED" : (g_activationFilled ? "waiting" : "needs T1 fill")) + "\n";
   dash += "──────────────────────────────────\n";
   dash += "  Expiry:  " + ExpiryNYDate + " NY (" + IntegerToString(daysLeft) + " days)" + expiryWarn + "\n";
   dash += "══════════════════════════════════\n";

   Comment(dash);
  }

//---------------------- Helpers: orders -----------------------------
double GetPoint() { return MarketInfo(Symbol(), MODE_POINT); }

//+------------------------------------------------------------------+
//| Get symbol digit precision                                       |
//+------------------------------------------------------------------+
int GetDigits() { return (int)MarketInfo(Symbol(), MODE_DIGITS); }
double NormalizePrice(double p) { return NormalizeDouble(p, GetDigits()); }

//+------------------------------------------------------------------+
//| Get current spread in points                                     |
//+------------------------------------------------------------------+
int CurrentSpreadPoints()
  {
   double sp = (Ask - Bid) / GetPoint();
   return (int)MathRound(sp);
  }

//+------------------------------------------------------------------+
//| Calculate lot size based on risk settings                        |
//+------------------------------------------------------------------+
double CalcLots()
  {
   if(!UseRiskPercent)
      return Lots;
   if(EmergencySL_Points <= 0)
      return Lots;
   double free = AccountFreeMargin();
   double riskMoney = free * (RiskPercent / 100.0);
   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double point   = GetPoint();
   if(tickVal <= 0 || tickSize <= 0)
      return Lots;
   double slPriceDist = EmergencySL_Points * point;
   double valuePerLot = (slPriceDist / tickSize) * tickVal;
   if(valuePerLot <= 0)
      return Lots;
   double lots = riskMoney / valuePerLot;
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / step) * step;
   lots = NormalizeDouble(lots, 2);
   if(lots < minLot)
      lots = minLot;
   return lots;
  }

//+------------------------------------------------------------------+
//| Check if any order exists with the given comment tag             |
//+------------------------------------------------------------------+
bool HasAnyWithTag(string tag)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      if(StringFind(OrderComment(), tag) < 0)
         continue;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if the activation order (T1) has been filled               |
//+------------------------------------------------------------------+
bool ActivationIsFilled()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      if(StringFind(OrderComment(), "MEP T1") < 0)
         continue;
      int t = OrderType();
      if(t == OP_BUY || t == OP_SELL)
        {
         g_t1 = OrderTicket();
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Determine pending order type based on bias and level vs price    |
//+------------------------------------------------------------------+
int PendingTypeForLevel(int bias, double level)
  {
   if(bias == 1)
     {
      if(Ask > level)
         return OP_BUYLIMIT;
      else
         return OP_BUYSTOP;
     }
   else
      if(bias == -1)
        {
         if(Bid < level)
            return OP_SELLLIMIT;
         else
            return OP_SELLSTOP;
        }
   return -1;
  }

//+------------------------------------------------------------------+
//| Calculate stop-loss price based on bias and entry                |
//+------------------------------------------------------------------+
double CalcSL(int bias, double entry)
  {
   if(EmergencySL_Points <= 0)
      return 0.0;
   double pt = GetPoint();
   if(bias == 1)
      return NormalizePrice(entry - EmergencySL_Points * pt);
   if(bias == -1)
      return NormalizePrice(entry + EmergencySL_Points * pt);
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Place a pending order at the specified level                     |
//+------------------------------------------------------------------+
bool PlacePending(string tag, int bias, double level, double tp)
  {
   if(!PlacePendingOrders)
      return false;
   int spread = CurrentSpreadPoints();
   if(spread > MaxSpreadPoints)
     {
      Print("MEP: Spread too wide (", spread, " > ", MaxSpreadPoints, ") - skipping ", tag);
      return false;
     }
   int type = PendingTypeForLevel(bias, level);
   if(type < 0)
      return false;
   double lots = CalcLots();
   double price = NormalizePrice(level);
   double sl = CalcSL(bias, price);
   double take = NormalizePrice(tp);
   int stopLvl = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLvl * GetPoint();

   // Ensure TP respects broker minimum stop distance
   if(take > 0)
     {
      if(bias == 1 && (take - price) < minDist)
         take = NormalizePrice(price + minDist);
      if(bias == -1 && (price - take) < minDist)
         take = NormalizePrice(price - minDist);
     }

   int ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, take, tag, MagicNumber, 0, clrNONE);
   if(ticket < 0)
     {
      Print("OrderSend failed for ", tag, " err=", GetLastError(),
            " type=", type, " price=", price, " sl=", sl, " tp=", take, " lots=", lots);
      return false;
     }

   Print("MEP: ", tag, " placed ticket=", ticket, " price=", price, " tp=", take);

   if(StringFind(tag, "T1") >= 0)
      g_t1 = ticket;
   if(StringFind(tag, "T2") >= 0)
      g_t2 = ticket;
   if(StringFind(tag, "T3") >= 0)
      g_t3 = ticket;
   return true;
  }

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA/symbol                     |
//+------------------------------------------------------------------+
void CancelAllPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      int t = OrderType();
      if(t == OP_BUYLIMIT || t == OP_BUYSTOP || t == OP_SELLLIMIT || t == OP_SELLSTOP)
        {
         int ticket = OrderTicket();
         if(!OrderDelete(ticket))
            Print("OrderDelete failed ticket=", ticket, " err=", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Close all open trades for this EA/symbol                         |
//+------------------------------------------------------------------+
void CloseAllOpenTrades()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      int t = OrderType();
      if(t == OP_BUY || t == OP_SELL)
        {
         int ticket = OrderTicket();
         double lots = OrderLots();
         bool ok = false;
         if(t == OP_BUY)
            ok = OrderClose(ticket, lots, Bid, Slippage, clrNONE);
         if(t == OP_SELL)
            ok = OrderClose(ticket, lots, Ask, Slippage, clrNONE);
         if(!ok)
            Print("OrderClose failed ticket=", ticket, " err=", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Ensure all open orders have the correct TP                       |
//+------------------------------------------------------------------+
void EnsureOpenOrdersTP(double tp)
  {
   double take = NormalizePrice(tp);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      int t = OrderType();
      if(t == OP_BUY || t == OP_SELL)
        {
         double curTP = OrderTakeProfit();
         if(curTP <= 0 || MathAbs(curTP - take) > (2 * GetPoint()))
           {
            bool ok = OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), take, 0, clrNONE);
            if(!ok)
               Print("OrderModify TP failed ticket=", OrderTicket(), " err=", GetLastError());
           }
        }
     }
  }

//---------------------- Session reset -------------------------------
//+------------------------------------------------------------------+
//| Reset all daily state variables for a new session                |
//+------------------------------------------------------------------+
void ResetDayState()
  {
   g_levelsReady = false;
   g_activationFilled = false;
   g_t1 = -1;
   g_t2 = -1;
   g_t3 = -1;
   g_O = g_H = g_L = g_CV = g_PRV = g_Net = g_TP = 0;
   g_bias = 0;
  }

//+------------------------------------------------------------------+
//| Initialize a new trading session                                 |
//+------------------------------------------------------------------+
bool StartNewSession(int newKey)
  {
   g_sessionKey = newKey;
   g_sessionStartUTC = SessionStartUTCFromKey(newKey);
   ResetDayState();
   CancelAllPendings();
   bool ok = LoadDailyLevels();
   if(!ok)
     {
      Print("MEP: Failed to load daily levels for session key ", newKey);
      return false;
     }
   g_levelsReady = true;
   UpdateDrawings();
   Print("MEP session ", newKey,
         " | O=", DoubleToStr(g_O, Digits),
         " H=", DoubleToStr(g_H, Digits),
         " L=", DoubleToStr(g_L, Digits),
         " CV=", DoubleToStr(g_CV, Digits),
         " PRV=", DoubleToStr(g_PRV, Digits),
         " Net=", DoubleToStr(g_Net, Digits),
         " TP=", DoubleToStr(g_TP, Digits),
         " bias=", g_bias);
   return true;
  }

//---------------------- MQL4 standard events ------------------------
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!SymbolAllowed())
     {
      Print("MathEdge Pro: Symbol not allowed by whitelist: ", Symbol());
      return(INIT_FAILED);
     }
   if(IsExpired(TimeGMT()))
     {
      Print("MathEdge Pro expired on ", ExpiryNYDate, " (NY time). Please contact provider for renewal.");
      return(INIT_FAILED);
     }

   int daysLeft = DaysUntilExpiry(TimeGMT());
   Print("MathEdge Pro v1.1 initialized on ", Symbol(),
         " | Expiry: ", ExpiryNYDate, " (", daysLeft, " days remaining)");

   if(daysLeft <= 7)
      Alert("MathEdge Pro: License expiring in ", daysLeft, " days! Contact provider for renewal.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");  // Clear dashboard on removal
   // Clean up chart objects
   if(DrawLevels)
     {
      ObjectDelete(0, "MEP_PRV");
      ObjectDelete(0, "MEP_CV");
      ObjectDelete(0, "MEP_H");
      ObjectDelete(0, "MEP_L");
      ObjectDelete(0, "MEP_TP");
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function - main trading logic                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!SymbolAllowed())
      return;

   datetime gmtNow = TimeGMT();

   // --- Expiry enforcement ---
   if(IsExpired(gmtNow))
     {
      CancelAllPendings();
      if(ExpiryCloseOpenTrades)
         CloseAllOpenTrades();
      Comment("MathEdge Pro expired on ", ExpiryNYDate, " (NY). Please contact provider for renewal.");
      return;
     }

   // --- Session management ---
   int key = CurrentSessionKey(gmtNow);
   if(key != g_sessionKey)
      StartNewSession(key);

   // --- Update dashboard every tick ---
   UpdateDashboard(gmtNow);

   // --- Trading window checks ---
   if(IsAfterWindowEnd(gmtNow))
     {
      if(CancelPendingsAfterWindow)
         CancelAllPendings();
      if(CloseOpenAtWindowEnd)
         CloseAllOpenTrades();
      return;
     }

   if(!IsWithinTradingWindow(gmtNow))
      return;

   if(!g_levelsReady)
      return;

   if(g_bias == 0)
      return;

   // --- Order management ---
   g_activationFilled = ActivationIsFilled();

   // T1: Activation order at PRV level
   if(!HasAnyWithTag("MEP T1"))
      PlacePending("MEP T1", g_bias, g_PRV, g_TP);

   // T2 & T3: Only after T1 is filled (activation confirmed)
   if(g_activationFilled)
     {
      EnsureOpenOrdersTP(g_TP);

      // T2: Second entry at extreme level (Low for buy, High for sell)
      if(!HasAnyWithTag("MEP T2"))
        {
         double lvl2 = (g_bias == 1 ? g_L : g_H);
         PlacePending("MEP T2", g_bias, lvl2, g_TP);
        }

      // T3: Third entry at CV level
      if(!HasAnyWithTag("MEP T3"))
         PlacePending("MEP T3", g_bias, g_CV, g_TP);
     }
  }
//+------------------------------------------------------------------+
