//+------------------------------------------------------------------+
//|                                        MomentumStopScalper.mq5   |
//|                                                                  |
//|  Chien luoc (phan tich tu video XAUUSD.ecn M1, lot 0.01):        |
//|   1. Luon giu 1 Buy Stop tai Ask + D va 1 Sell Stop tai Bid - D  |
//|      (video: D = 0.05$, spread 0.09 -> 2 lenh cho cach nhau 0.19)|
//|   2. Lenh cho nao khop -> dat ngay lenh cho moi cung chieu       |
//|      => gia chay manh thi nhoi lenh theo da (pyramiding).        |
//|   3. Moi lenh co SL co dinh (video: 0.30$) va Trailing Stop      |
//|      (video: 0.30$, chi bat dau khi lai > 0.30$).                |
//|   4. Toi da N lenh mo cung luc (video: 7). Du N thi ngung dat    |
//|      lenh cho moi.                                               |
//|   5. Lenh cho bi bo xa (gia chay nguoc) se duoc keo theo gia.    |
//|                                                                  |
//|  Don vi "pip" trong EA: pip = point x10 neu symbol co 3 hoac 5   |
//|  so le, nguoc lai pip = point. Vang (XAUUSD 2 hoac 3 so le):     |
//|  1 pip = 0.01$  -> 5 pip = 0.05$, 30 pip = 0.30$ (dung video).   |
//|                                                                  |
//|  YEU CAU: tai khoan HEDGING (giu Buy va Sell cung luc).          |
//+------------------------------------------------------------------+
#property copyright   "hoi1986"
#property version     "1.00"
#property description "Momentum Stop Scalper: Buy Stop/Sell Stop bam sat gia, SL co dinh + Trailing, nhoi lenh theo da."
#property description "Mac dinh = thong so phan tich tu video (XAUUSD, 0.01 lot, D=5 pip, SL=30, Trailing=30, toi da 7 lenh)."
#property description "Yeu cau tai khoan HEDGING. Tu dong thich ung so le, hau to symbol, kieu khop lenh, stops/freeze level cua tung san."

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_MODE_FIXED   = 0, // Lot co dinh
   LOT_MODE_BALANCE = 1  // Lot tu dong theo so du
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== VAO LENH (lenh cho Stop) ==="
input double InpEntryDistancePips     = 5;     // Khoang cach lenh cho so voi gia (pip)
input double InpPendingStepPips       = 25;    // Keo lenh cho theo gia khi bi bo xa them (pip, 0 = tat)
input int    InpMaxPositions          = 7;     // So lenh mo toi da Buy+Sell (0 = khong gioi han)
input bool   InpDeletePendingAtMax    = false; // Xoa lenh cho khi da du so lenh toi da

input group "=== KHOI LUONG ==="
input ENUM_LOT_MODE InpLotMode        = LOT_MODE_FIXED; // Cach tinh lot
input double InpLots                  = 0.01;  // Lot (co dinh, hoac lot cho moi buoc so du)
input double InpBalancePerStep        = 200.0; // So du cho moi buoc lot (che do tu dong)

input group "=== CAT LO / TRAILING ==="
input double InpStopLossPips          = 30;    // Stop Loss (pip, 0 = khong dat)
input double InpTakeProfitPips        = 0;     // Take Profit (pip, 0 = khong dat)
input double InpTrailingStopPips      = 30;    // Trailing Stop (pip, 0 = tat)
input double InpTrailingStartPips     = 30;    // Bat dau trailing khi lai > (pip)
input double InpTrailingStepPips      = 1;     // Buoc doi SL toi thieu (pip)
input bool   InpAlignSLToFill         = true;  // Dat lai SL theo gia khop thuc te (bu truot gia)

input group "=== BO LOC ==="
input double InpMaxSpreadPips         = 15;    // Spread toi da de dat lenh (pip, 0 = tat)
input bool   InpDeletePendingOnFilter = true;  // Xoa lenh cho khi bo loc khong cho vao lenh
input bool   InpUseTimeFilter         = false; // Bat bo loc gio (gio may chu)
input int    InpStartHour             = 1;     // Gio bat dau (0-23)
input int    InpStartMinute           = 5;     // Phut bat dau (0-59)
input int    InpEndHour               = 23;    // Gio ket thuc (0-23)
input int    InpEndMinute             = 50;    // Phut ket thuc (0-59)

input group "=== BAO VE TAI KHOAN (0 = tat) ==="
input double InpMaxDailyLossPct       = 0;     // Lo toi da trong ngay (% so du dau ngay)
input double InpDailyTargetPct        = 0;     // Muc tieu lai trong ngay (% so du dau ngay)

input group "=== KHAC ==="
input ulong  InpMagic                 = 20261012; // Magic number
input string InpOrderComment          = "MSS";    // Ghi chu lenh
input double InpSlippagePips          = 5;     // Truot gia toi da khi dong lenh thi truong (pip)
input bool   InpDeletePendingOnExit   = true;  // Xoa lenh cho khi go EA khoi bieu do
input bool   InpShowPanel             = true;  // Hien bang thong tin tren bieu do

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define EA_NAME "Momentum Stop Scalper v1.00"

//--- symbol
string   g_sym        = "";
int      g_digits     = 0;
double   g_point      = 0.0;
double   g_tick       = 0.0;   // tick size
double   g_pip        = 0.0;
bool     g_isTester   = false;
bool     g_showPanel  = true;

//--- trade settings (tu dong do theo san)
ENUM_ORDER_TYPE_FILLING g_fillPending   = ORDER_FILLING_RETURN;
ENUM_ORDER_TYPE_FILLING g_fillMarket    = ORDER_FILLING_FOK;
bool                    g_fillPendingOk = false;
bool                    g_fillMarketOk  = false;
ENUM_ORDER_TYPE_TIME    g_typeTime      = ORDER_TIME_GTC;

//--- runtime
ulong    g_nowMs          = 0;     // thoi gian thi truong (ms) cua tick hien tai
ulong    g_entryBlockMs   = 0;     // tam khoa dat/sua lenh cho den moc nay
ulong    g_mgmtBlockMs    = 0;     // tam khoa sua SL/dong lenh den moc nay
double   g_extraEntry     = 0.0;   // khoang cach cong them neu san tu choi gia qua gan
int      g_badPriceStreak = 0;
int      g_okPlaceCount   = 0;
datetime g_dayStart       = 0;
double   g_dayStartBal    = 0.0;
bool     g_dayHalted      = false;
string   g_status         = "Khoi dong";
ulong    g_lastPanelMs    = 0;
ulong    g_lastStatsMs    = 0;
ulong    g_lastProcessMs  = 0;
ulong    g_lastErrPrintMs = 0;
uint     g_lastErrCode    = 0;
bool     g_busy           = false;

//--- thong ke trong ngay (chi cac lenh cua EA nay)
int      g_dTrades = 0;
double   g_dProfit = 0.0;
double   g_dComm   = 0.0;
double   g_dSwap   = 0.0;
double   g_dFee    = 0.0;

//+------------------------------------------------------------------+
//| Helpers: don vi gia                                              |
//+------------------------------------------------------------------+
double PipsToPrice(const double pips) { return pips * g_pip; }

double NormUp(const double price)
  {
   return NormalizeDouble(MathCeil(price / g_tick - 1e-7) * g_tick, g_digits);
  }

double NormDown(const double price)
  {
   return NormalizeDouble(MathFloor(price / g_tick + 1e-7) * g_tick, g_digits);
  }

double StopsLevelDist()  { return (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL)  * g_point; }
double FreezeLevelDist() { return (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_FREEZE_LEVEL) * g_point; }

ulong SlippagePoints()
  {
   double pts = MathRound(PipsToPrice(InpSlippagePips) / g_point);
   if(pts < 0.0)
      pts = 0.0;
   return (ulong)pts;
  }

bool IsOwn(const string sym, const long magic)
  {
   return (sym == g_sym && (ulong)magic == InpMagic);
  }

bool IsDone(const uint rc)
  {
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
  }

//+------------------------------------------------------------------+
//| Khoang cach dat lenh cho (ton trong stops level cua san)         |
//+------------------------------------------------------------------+
double EntryDistance()
  {
   double d     = PipsToPrice(InpEntryDistancePips) + g_extraEntry;
   double stops = StopsLevelDist();
   if(stops > 0.0 && d < stops)
      d = stops;
   if(d < g_tick)
      d = g_tick;
   return d;
  }

//+------------------------------------------------------------------+
//| Khoi luong                                                       |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double vmin  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      vstep = (vmin > 0.0 ? vmin : 0.01);
   lots = MathFloor(lots / vstep + 1e-7) * vstep;
   if(lots < vmin)
      lots = vmin;
   if(vmax > 0.0 && lots > vmax)
      lots = vmax;
   int vd = (int)MathMax(0.0, MathCeil(-MathLog10(vstep) - 1e-9));
   return NormalizeDouble(lots, vd);
  }

double CalcLots()
  {
   double lots = InpLots;
   if(InpLotMode == LOT_MODE_BALANCE && InpBalancePerStep > 0.0)
     {
      double steps = MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpBalancePerStep);
      if(steps < 1.0)
         steps = 1.0;
      lots = InpLots * steps;
     }
   return NormalizeLots(lots);
  }

bool MarginOk(const ENUM_ORDER_TYPE type, const double lots, const double price)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(type, g_sym, lots, price, margin))
      return true; // khong tinh duoc -> de may chu quyet dinh
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin * 1.1);
  }

//+------------------------------------------------------------------+
//| Kieu het han lenh cho theo san                                   |
//+------------------------------------------------------------------+
void SetupExpiration()
  {
   int mode = (int)SymbolInfoInteger(g_sym, SYMBOL_EXPIRATION_MODE);
   if(mode == 0 || (mode & SYMBOL_EXPIRATION_GTC) != 0)
      g_typeTime = ORDER_TIME_GTC;
   else
      if((mode & SYMBOL_EXPIRATION_DAY) != 0)
         g_typeTime = ORDER_TIME_DAY;
      else
         if((mode & SYMBOL_EXPIRATION_SPECIFIED) != 0)
            g_typeTime = ORDER_TIME_SPECIFIED;
         else
            g_typeTime = ORDER_TIME_SPECIFIED_DAY;
  }

datetime ExpirationTime()
  {
   if(g_typeTime == ORDER_TIME_SPECIFIED || g_typeTime == ORDER_TIME_SPECIFIED_DAY)
      return TimeCurrent() + 86400;
   return 0;
  }

//+------------------------------------------------------------------+
//| Gui lenh, tu thu cac kieu khop lenh (FOK/IOC/RETURN) neu bi tu choi|
//+------------------------------------------------------------------+
void AddFill(ENUM_ORDER_TYPE_FILLING &arr[], int &n, const ENUM_ORDER_TYPE_FILLING v)
  {
   for(int i = 0; i < n; i++)
      if(arr[i] == v)
         return;
   if(n < ArraySize(arr))
     {
      arr[n] = v;
      n++;
     }
  }

bool SendRequest(MqlTradeRequest &req, MqlTradeResult &res, const bool needFill, const bool isPending)
  {
   if(!needFill)
     {
      ZeroMemory(res);
      bool sent = OrderSend(req, res);
      return (sent && IsDone(res.retcode));
     }

   ENUM_ORDER_TYPE_FILLING cand[4];
   int n = 0;
   if(isPending && g_fillPendingOk)
      AddFill(cand, n, g_fillPending);
   if(!isPending && g_fillMarketOk)
      AddFill(cand, n, g_fillMarket);
   long flags = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((flags & SYMBOL_FILLING_FOK) != 0)
      AddFill(cand, n, ORDER_FILLING_FOK);
   if((flags & SYMBOL_FILLING_IOC) != 0)
      AddFill(cand, n, ORDER_FILLING_IOC);
   AddFill(cand, n, ORDER_FILLING_RETURN);
   AddFill(cand, n, ORDER_FILLING_FOK);
   AddFill(cand, n, ORDER_FILLING_IOC);

   for(int i = 0; i < n; i++)
     {
      req.type_filling = cand[i];
      ZeroMemory(res);
      bool sent = OrderSend(req, res);
      if(sent && IsDone(res.retcode))
        {
         if(isPending)
           {
            g_fillPending   = cand[i];
            g_fillPendingOk = true;
           }
         else
           {
            g_fillMarket   = cand[i];
            g_fillMarketOk = true;
           }
         return true;
        }
      if(res.retcode != TRADE_RETCODE_INVALID_FILL)
         return false;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Xu ly loi: tam dung hop ly, khong spam may chu                   |
//+------------------------------------------------------------------+
void OnTradeFail(const string what, const MqlTradeResult &res, const bool entry)
  {
   uint  rc   = res.retcode;
   ulong wait = 1000;
   switch(rc)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_FROZEN:
      case TRADE_RETCODE_NO_CHANGES:
      case TRADE_RETCODE_ORDER_CHANGED:
      case 10035: // INVALID_ORDER
      case 10036: // POSITION_CLOSED
         wait = 0;      // thu lai o tick sau
         break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_LOCKED:
         wait = 2000;
         break;
      case TRADE_RETCODE_NO_MONEY:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case 10040: // LIMIT_POSITIONS
         wait = 15000;
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_ONLY_REAL:
      case 10042: // LONG_ONLY
      case 10043: // SHORT_ONLY
      case 10044: // CLOSE_ONLY
      case 10046: // HEDGE_PROHIBITED
         wait = 60000;
         break;
      default:
         wait = 1000;
         break;
     }

   ulong until = g_nowMs + wait;
   if(entry)
     {
      if(until > g_entryBlockMs)
         g_entryBlockMs = until;
     }
   else
     {
      if(until > g_mgmtBlockMs)
         g_mgmtBlockMs = until;
     }

//--- san tu choi gia qua gan nhieu lan lien tiep -> tu noi rong khoang cach
   if(entry && (rc == TRADE_RETCODE_INVALID_PRICE || rc == TRADE_RETCODE_INVALID_STOPS))
     {
      g_badPriceStreak++;
      double inc = MathMax(g_tick, PipsToPrice(InpEntryDistancePips) * 0.2);
      double cap = MathMax(PipsToPrice(InpEntryDistancePips) * 3.0, g_tick * 20.0);
      if(g_badPriceStreak >= 3 && g_extraEntry + inc <= cap + g_tick * 0.5)
        {
         g_extraEntry    += inc;
         g_badPriceStreak = 0;
         PrintFormat("[MSS] San tu choi gia lenh cho qua gan -> tang khoang cach them %s (tong them %s)",
                     DoubleToString(inc, g_digits), DoubleToString(g_extraEntry, g_digits));
        }
     }

//--- ghi log co gioi han tan suat
   if(rc != g_lastErrCode || g_nowMs < g_lastErrPrintMs || g_nowMs - g_lastErrPrintMs >= 5000)
     {
      PrintFormat("[MSS] %s that bai: retcode=%u (%s), loi=%d", what, rc, res.comment, GetLastError());
      g_lastErrCode    = rc;
      g_lastErrPrintMs = g_nowMs;
     }
  }

void OnPlaceOk()
  {
   g_badPriceStreak = 0;
   if(g_extraEntry > 0.0)
     {
      g_okPlaceCount++;
      if(g_okPlaceCount >= 50)
        {
         double inc = MathMax(g_tick, PipsToPrice(InpEntryDistancePips) * 0.2);
         g_extraEntry = MathMax(0.0, g_extraEntry - inc);
         g_okPlaceCount = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| SL/TP cho lenh cho                                               |
//+------------------------------------------------------------------+
void PendingStops(const ENUM_ORDER_TYPE type, const double price, double &sl, double &tp)
  {
   double stops  = StopsLevelDist();
   double slDist = (InpStopLossPips > 0.0)   ? MathMax(PipsToPrice(InpStopLossPips),   stops) : 0.0;
   double tpDist = (InpTakeProfitPips > 0.0) ? MathMax(PipsToPrice(InpTakeProfitPips), stops) : 0.0;
   sl = 0.0;
   tp = 0.0;
   if(type == ORDER_TYPE_BUY_STOP)
     {
      if(slDist > 0.0)
         sl = NormDown(price - slDist);
      if(tpDist > 0.0)
         tp = NormUp(price + tpDist);
     }
   else
     {
      if(slDist > 0.0)
         sl = NormUp(price + slDist);
      if(tpDist > 0.0)
         tp = NormDown(price - tpDist);
     }
  }

//+------------------------------------------------------------------+
//| Cac lenh giao dich co ban                                        |
//+------------------------------------------------------------------+
bool PlacePending(const ENUM_ORDER_TYPE type, const double price, const double lots)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   double sl = 0.0, tp = 0.0;
   PendingStops(type, price, sl, tp);
   req.action     = TRADE_ACTION_PENDING;
   req.symbol     = g_sym;
   req.magic      = InpMagic;
   req.volume     = lots;
   req.type       = type;
   req.price      = price;
   req.sl         = sl;
   req.tp         = tp;
   req.deviation  = SlippagePoints();
   req.type_time  = g_typeTime;
   req.expiration = ExpirationTime();
   req.comment    = InpOrderComment;
   if(SendRequest(req, res, true, true))
     {
      OnPlaceOk();
      return true;
     }
   OnTradeFail(type == ORDER_TYPE_BUY_STOP ? "Dat Buy Stop" : "Dat Sell Stop", res, true);
   return false;
  }

bool ModifyPending(const ulong ticket, const ENUM_ORDER_TYPE type, const double price)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   double sl = 0.0, tp = 0.0;
   PendingStops(type, price, sl, tp);
   req.action     = TRADE_ACTION_MODIFY;
   req.order      = ticket;
   req.symbol     = g_sym;
   req.magic      = InpMagic;
   req.price      = price;
   req.sl         = sl;
   req.tp         = tp;
   req.type_time  = g_typeTime;
   req.expiration = ExpirationTime();
   if(SendRequest(req, res, false, true))
      return true;
   OnTradeFail("Keo lenh cho", res, true);
   return false;
  }

bool DeletePending(const ulong ticket)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   req.symbol = g_sym;
   req.magic  = InpMagic;
   if(SendRequest(req, res, false, true))
      return true;
   OnTradeFail("Xoa lenh cho", res, true);
   return false;
  }

bool ModifySL(const ulong ticket, const double sl, const double tp)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = g_sym;
   req.magic    = InpMagic;
   req.sl       = sl;
   req.tp       = tp;
   if(SendRequest(req, res, false, false))
      return true;
   OnTradeFail("Sua SL", res, false);
   return false;
  }

bool ClosePosition(const ulong ticket, const ENUM_POSITION_TYPE type, const double volume)
  {
   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk))
      return false;
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.position  = ticket;
   req.symbol    = g_sym;
   req.magic     = InpMagic;
   req.volume    = volume;
   req.deviation = SlippagePoints();
   req.comment   = InpOrderComment;
   if(type == POSITION_TYPE_BUY)
     {
      req.type  = ORDER_TYPE_SELL;
      req.price = tk.bid;
     }
   else
     {
      req.type  = ORDER_TYPE_BUY;
      req.price = tk.ask;
     }
   if(SendRequest(req, res, true, false))
      return true;
   OnTradeFail("Dong lenh", res, false);
   return false;
  }

//+------------------------------------------------------------------+
//| Quan ly lenh dang mo: dam bao SL + Trailing Stop                 |
//+------------------------------------------------------------------+
void ManagePositions(const MqlTick &tk, int &nBuy, int &nSell, double &floating)
  {
   bool   canModify = (g_nowMs >= g_mgmtBlockMs);
   double slDist    = (InpStopLossPips > 0.0)     ? PipsToPrice(InpStopLossPips)     : 0.0;
   double trDist    = (InpTrailingStopPips > 0.0) ? PipsToPrice(InpTrailingStopPips) : 0.0;
   double trStart   = PipsToPrice(InpTrailingStartPips);
   double trStep    = MathMax(PipsToPrice(InpTrailingStepPips), g_tick);
   double stops     = StopsLevelDist();
   double freeze    = FreezeLevelDist();
   double half      = g_tick * 0.5;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(type == POSITION_TYPE_BUY)
         nBuy++;
      else
         nSell++;

      if(!canModify)
         continue;

      if(type == POSITION_TYPE_BUY)
        {
         double price  = tk.bid;
         double target = sl;
         //--- SL co dinh tinh tu gia khop thuc te
         if(slDist > 0.0)
           {
            double want = NormDown(open - slDist);
            if(sl <= 0.0 || (InpAlignSLToFill && sl < want - half))
               target = want;
           }
         //--- Trailing Stop
         if(trDist > 0.0 && price - open > trStart)
           {
            double nsl = NormDown(price - trDist);
            if(nsl > target + half && (sl <= 0.0 || nsl >= sl + trStep - half))
               target = nsl;
           }
         if(target <= 0.0 || MathAbs(target - sl) < half)
            continue;
         if(price <= target)                  // gia da vuot qua muc SL mong muon
           {
            ClosePosition(ticket, type, vol);
            continue;
           }
         if(price - target < stops)           // qua gan theo quy dinh san
            continue;
         if(sl > 0.0 && price - sl <= freeze) // lenh dang bi dong bang
            continue;
         ModifySL(ticket, target, tp);
        }
      else
        {
         double price  = tk.ask;
         double target = sl;
         if(slDist > 0.0)
           {
            double want = NormUp(open + slDist);
            if(sl <= 0.0 || (InpAlignSLToFill && sl > want + half))
               target = want;
           }
         if(trDist > 0.0 && open - price > trStart)
           {
            double nsl = NormUp(price + trDist);
            if((target <= 0.0 || nsl < target - half) && (sl <= 0.0 || nsl <= sl - trStep + half))
               target = nsl;
           }
         if(target <= 0.0 || MathAbs(target - sl) < half)
            continue;
         if(price >= target)
           {
            ClosePosition(ticket, type, vol);
            continue;
           }
         if(target - price < stops)
            continue;
         if(sl > 0.0 && sl - price <= freeze)
            continue;
         ModifySL(ticket, target, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Quan ly cap lenh cho Buy Stop / Sell Stop                        |
//+------------------------------------------------------------------+
void ManagePendings(const MqlTick &tk, const int nPositions, const bool allowEntry)
  {
   ulong  bsTicket = 0, ssTicket = 0;
   double bsPrice  = 0.0, ssPrice = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
         continue;
      ENUM_ORDER_TYPE type  = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double          price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(type == ORDER_TYPE_BUY_STOP)
        {
         if(bsTicket == 0)
           {
            bsTicket = ticket;
            bsPrice  = price;
           }
         else
            DeletePending(ticket);  // chi giu 1 Buy Stop
        }
      else
         if(type == ORDER_TYPE_SELL_STOP)
           {
            if(ssTicket == 0)
              {
               ssTicket = ticket;
               ssPrice  = price;
              }
            else
               DeletePending(ticket);  // chi giu 1 Sell Stop
           }
     }

   bool atMax = (InpMaxPositions > 0 && nPositions >= InpMaxPositions);
   if(!allowEntry || atMax)
     {
      bool del = (!allowEntry && InpDeletePendingOnFilter) || (atMax && InpDeletePendingAtMax);
      if(del)
        {
         if(bsTicket > 0)
            DeletePending(bsTicket);
         if(ssTicket > 0)
            DeletePending(ssTicket);
        }
      return;
     }

   if(g_nowMs < g_entryBlockMs)
      return;

   ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(g_sym, SYMBOL_TRADE_MODE);
   bool allowBuy  = (tm == SYMBOL_TRADE_MODE_FULL || tm == SYMBOL_TRADE_MODE_LONGONLY);
   bool allowSell = (tm == SYMBOL_TRADE_MODE_FULL || tm == SYMBOL_TRADE_MODE_SHORTONLY);

   double dist     = EntryDistance();
   double wantBuy  = NormUp(tk.ask + dist);
   double wantSell = NormDown(tk.bid - dist);
   double step     = PipsToPrice(InpPendingStepPips);
   double freeze   = FreezeLevelDist();
   double half     = g_tick * 0.5;
   double lots     = CalcLots();

//--- Buy Stop: dat moi neu chua co, keo xuong neu gia da giam xa
   if(allowBuy)
     {
      if(bsTicket == 0)
        {
         if(MarginOk(ORDER_TYPE_BUY, lots, wantBuy))
            PlacePending(ORDER_TYPE_BUY_STOP, wantBuy, lots);
        }
      else
         if(step > 0.0 && bsPrice - wantBuy >= step - half && bsPrice - tk.ask > freeze)
            ModifyPending(bsTicket, ORDER_TYPE_BUY_STOP, wantBuy);
     }

//--- Sell Stop: dat moi neu chua co, keo len neu gia da tang xa
   if(allowSell && g_nowMs >= g_entryBlockMs)
     {
      if(ssTicket == 0)
        {
         if(MarginOk(ORDER_TYPE_SELL, lots, wantSell))
            PlacePending(ORDER_TYPE_SELL_STOP, wantSell, lots);
        }
      else
         if(step > 0.0 && wantSell - ssPrice >= step - half && tk.bid - ssPrice > freeze)
            ModifyPending(ssTicket, ORDER_TYPE_SELL_STOP, wantSell);
     }
  }

//+------------------------------------------------------------------+
//| Dong tat ca / xoa tat ca (chi cua EA nay)                        |
//+------------------------------------------------------------------+
void DeleteAllPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         DeletePending(ticket);
     }
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
         continue;
      ClosePosition(ticket, (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE), PositionGetDouble(POSITION_VOLUME));
     }
  }

void CountOwn(int &nBuy, int &nSell, int &nBuyStop, int &nSellStop, double &floating)
  {
   nBuy = 0;
   nSell = 0;
   nBuyStop = 0;
   nSellStop = 0;
   floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         nBuy++;
      else
         nSell++;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP)
         nBuyStop++;
      else
         if(type == ORDER_TYPE_SELL_STOP)
            nSellStop++;
     }
  }

//+------------------------------------------------------------------+
//| Kiem tra quyen giao dich                                         |
//+------------------------------------------------------------------+
bool TradingAllowed(string &why)
  {
   if(g_isTester)
      return true;
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
     {
      why = "Mat ket noi may chu";
      return false;
     }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
     {
      why = "Nut Algo Trading tren terminal dang TAT";
      return false;
     }
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
     {
      why = "EA chua duoc phep giao dich (tick 'Allow Algo Trading')";
      return false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
     {
      why = "Tai khoan khong duoc phep giao dich (dang dung mat khau investor?)";
      return false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
     {
      why = "San khong cho phep giao dich bang EA tren tai khoan nay";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Bo loc vao lenh                                                  |
//+------------------------------------------------------------------+
bool InTradingTime()
  {
   if(!InpUseTimeFilter)
      return true;
   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   int now = s.hour * 60 + s.min;
   int st  = InpStartHour * 60 + InpStartMinute;
   int en  = InpEndHour * 60 + InpEndMinute;
   if(st == en)
      return true;
   if(st < en)
      return (now >= st && now < en);
   return (now >= st || now < en); // khung gio qua dem
  }

bool EntryFiltersOk(const MqlTick &tk, string &why)
  {
   if(g_dayHalted)
     {
      why = "Da cham gioi han trong ngay -> tam dung den ngay moi";
      return false;
     }
   double spread = tk.ask - tk.bid;
   if(InpMaxSpreadPips > 0.0 && spread > PipsToPrice(InpMaxSpreadPips) + g_tick * 0.5)
     {
      why = StringFormat("Spread cao %.1f pip > %.1f pip -> tam dung", spread / g_pip, InpMaxSpreadPips);
      return false;
     }
   if(!InTradingTime())
     {
      why = "Ngoai khung gio giao dich";
      return false;
     }
   ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(g_sym, SYMBOL_TRADE_MODE);
   if(tm == SYMBOL_TRADE_MODE_DISABLED || tm == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      why = "San khong cho mo lenh moi tren ma nay";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Gioi han lai/lo trong ngay (luu qua Global Variables)            |
//+------------------------------------------------------------------+
string GvName(const string key)
  {
   return "MSS_" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "_" + (string)InpMagic + "_" + key;
  }

void CheckNewDay()
  {
   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   s.hour = 0;
   s.min  = 0;
   s.sec  = 0;
   datetime ds = StructToTime(s);
   if(ds == g_dayStart)
      return;
   g_dayStart = ds;

   string gd = GvName("D"), gb = GvName("B"), gh = GvName("H");
   if(GlobalVariableCheck(gd) && (datetime)(long)GlobalVariableGet(gd) == ds && GlobalVariableCheck(gb))
     {
      g_dayStartBal = GlobalVariableGet(gb);
      g_dayHalted   = (GlobalVariableCheck(gh) && GlobalVariableGet(gh) > 0.5);
     }
   else
     {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dayHalted   = false;
      GlobalVariableSet(gd, (double)ds);
      GlobalVariableSet(gb, g_dayStartBal);
      GlobalVariableSet(gh, 0.0);
     }
   g_lastStatsMs = 0;
  }

bool CheckDailyGuard()
  {
   if(InpMaxDailyLossPct <= 0.0 && InpDailyTargetPct <= 0.0)
      return false;
   if(g_dayHalted)
      return true;
   if(g_dayStartBal <= 0.0)
      return false;
   double pnl = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBal;
   string reason = "";
   if(InpMaxDailyLossPct > 0.0 && pnl <= -g_dayStartBal * InpMaxDailyLossPct / 100.0)
      reason = StringFormat("lo trong ngay %.2f (>= %.2f%%)", pnl, InpMaxDailyLossPct);
   else
      if(InpDailyTargetPct > 0.0 && pnl >= g_dayStartBal * InpDailyTargetPct / 100.0)
         reason = StringFormat("dat muc tieu ngay %.2f (>= %.2f%%)", pnl, InpDailyTargetPct);
   if(reason == "")
      return false;
   g_dayHalted = true;
   GlobalVariableSet(GvName("H"), 1.0);
   PrintFormat("[MSS] Tam dung den ngay moi: %s. Dong toan bo lenh cua EA.", reason);
   return true;
  }

//+------------------------------------------------------------------+
//| Thong ke trong ngay                                              |
//+------------------------------------------------------------------+
void UpdateDailyStats()
  {
   g_dTrades = 0;
   g_dProfit = 0.0;
   g_dComm   = 0.0;
   g_dSwap   = 0.0;
   g_dFee    = 0.0;
   if(g_dayStart <= 0)
      return;
   if(!HistorySelect(g_dayStart, TimeCurrent() + 86400))
      return;
   int  total = HistoryDealsTotal();
   long ids[];
   int  nIds = 0;
   ArrayResize(ids, 0, 1024);
//--- lan 1: cac position do EA mo trong ngay
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(!IsOwn(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      ArrayResize(ids, nIds + 1, 1024);
      ids[nIds] = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      nIds++;
     }
   g_dTrades = nIds;
   if(nIds > 1)
      ArraySort(ids);
//--- lan 2: cong don lai/lo, phi (ca deal dong boi SL/TP)
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != g_sym)
         continue;
      bool own = ((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) == InpMagic);
      if(!own && nIds > 0)
        {
         long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int  k   = ArrayBsearch(ids, pid);
         own = (k >= 0 && k < nIds && ids[k] == pid);
        }
      if(!own)
         continue;
      g_dProfit += HistoryDealGetDouble(d, DEAL_PROFIT);
      g_dComm   += HistoryDealGetDouble(d, DEAL_COMMISSION);
      g_dSwap   += HistoryDealGetDouble(d, DEAL_SWAP);
      g_dFee    += HistoryDealGetDouble(d, DEAL_FEE);
     }
  }

//+------------------------------------------------------------------+
//| Bang thong tin                                                   |
//+------------------------------------------------------------------+
void UpdatePanel(const bool force)
  {
   if(!g_showPanel)
      return;
   ulong now = GetTickCount64();
   if(!force && now >= g_lastPanelMs && now - g_lastPanelMs < 500)
      return;
   g_lastPanelMs = now;

   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk))
      return;
   int    nb = 0, ns = 0, nbs = 0, nss = 0;
   double fl = 0.0;
   CountOwn(nb, ns, nbs, nss, fl);
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   double net = g_dProfit + g_dComm + g_dSwap + g_dFee;

   string s = EA_NAME + "\n";
   s += StringFormat("%s | Magic %s | pip = %s\n", g_sym, (string)InpMagic, DoubleToString(g_pip, g_digits));
   s += StringFormat("Spread: %.1f pip (toi da %.1f) | Vao lenh: +/-%s | SL %s | Trail %s\n",
                     (tk.ask - tk.bid) / g_pip, InpMaxSpreadPips,
                     DoubleToString(EntryDistance(), g_digits),
                     DoubleToString(PipsToPrice(InpStopLossPips), g_digits),
                     DoubleToString(PipsToPrice(InpTrailingStopPips), g_digits));
   s += StringFormat("Lenh mo: Buy %d | Sell %d | Toi da %d   Lenh cho: BuyStop %d | SellStop %d\n",
                     nb, ns, InpMaxPositions, nbs, nss);
   s += StringFormat("Lai/lo tha noi: %.2f %s\n", fl, cur);
   s += StringFormat("Hom nay: %d lenh | Lai gop %.2f | Phi %.2f | Swap %.2f | RONG %.2f %s\n",
                     g_dTrades, g_dProfit, g_dComm + g_dFee, g_dSwap, net, cur);
   s += "Trang thai: " + g_status;
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Vong xu ly chinh                                                 |
//+------------------------------------------------------------------+
void ProcessCore()
  {
   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk) || tk.bid <= 0.0 || tk.ask <= 0.0 || tk.ask < tk.bid)
      return;
   g_nowMs = (tk.time_msc > 0) ? (ulong)tk.time_msc : (ulong)TimeCurrent() * 1000;
   g_lastProcessMs = GetTickCount64();
   CheckNewDay();

   string why = "";
   if(!TradingAllowed(why))
     {
      g_status = why;
      return;
     }

   int    nBuy = 0, nSell = 0;
   double floating = 0.0;
   ManagePositions(tk, nBuy, nSell, floating);

   if(CheckDailyGuard())
     {
      CloseAllPositions();
      DeleteAllPendings();
      g_status = "Da cham gioi han trong ngay -> tam dung den ngay moi";
      return;
     }

   bool allowEntry = EntryFiltersOk(tk, why);
   ManagePendings(tk, nBuy + nSell, allowEntry);
   g_status = allowEntry ? "Dang chay" : why;
  }

void Process()
  {
   if(g_busy)
      return;
   g_busy = true;
   ProcessCore();
   g_busy = false;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_sym      = _Symbol;
   g_isTester = (MQLInfoInteger(MQL_TESTER) != 0);
   g_showPanel = InpShowPanel && (!g_isTester || MQLInfoInteger(MQL_VISUAL_MODE) != 0);

   if(!SymbolSelect(g_sym, true))
     {
      Print("[MSS] Khong chon duoc symbol ", g_sym);
      return INIT_FAILED;
     }
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tick   = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_point <= 0.0)
      g_point = MathPow(10.0, -g_digits);
   if(g_tick <= 0.0)
      g_tick = g_point;
   g_pip = (g_digits == 3 || g_digits == 5) ? g_point * 10.0 : g_point;

//--- kiem tra tham so
   if(InpEntryDistancePips <= 0.0)
     {
      Print("[MSS] Khoang cach vao lenh phai > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpStopLossPips < 0.0 || InpTakeProfitPips < 0.0 || InpTrailingStopPips < 0.0 ||
      InpTrailingStartPips < 0.0 || InpTrailingStepPips < 0.0 || InpPendingStepPips < 0.0 ||
      InpMaxSpreadPips < 0.0 || InpSlippagePips < 0.0 || InpMaxPositions < 0 ||
      InpMaxDailyLossPct < 0.0 || InpDailyTargetPct < 0.0)
     {
      Print("[MSS] Tham so khong duoc am");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLots <= 0.0 || (InpLotMode == LOT_MODE_BALANCE && InpBalancePerStep <= 0.0))
     {
      Print("[MSS] Lot / so du moi buoc phai > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 0 || InpEndHour > 23 ||
      InpStartMinute < 0 || InpStartMinute > 59 || InpEndMinute < 0 || InpEndMinute > 59)
     {
      Print("[MSS] Gio/phut khong hop le");
      return INIT_PARAMETERS_INCORRECT;
     }

//--- chien luoc can giu Buy va Sell cung luc -> bat buoc tai khoan Hedging
   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      string msg = "[MSS] Tai khoan dang o che do NETTING/EXCHANGE. Chien luoc can giu Buy va Sell cung luc "
                   "-> hay mo tai khoan HEDGING (hau het san forex MT5 deu co).";
      Print(msg);
      Alert(msg);
      return INIT_FAILED;
     }

   double vmin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   if(InpLotMode == LOT_MODE_FIXED && InpLots < vmin)
      PrintFormat("[MSS] Canh bao: lot %.2f nho hon lot toi thieu cua san (%.2f) -> dung %.2f", InpLots, vmin, vmin);

   SetupExpiration();
   CheckNewDay();

   long spreadPts = SymbolInfoInteger(g_sym, SYMBOL_SPREAD);
   PrintFormat("[MSS] %s | digits=%d point=%s pip=%s | Vao lenh +/-%s | SL %s | TP %s | Trailing %s (bat dau khi lai > %s, buoc %s)",
               g_sym, g_digits, DoubleToString(g_point, g_digits), DoubleToString(g_pip, g_digits),
               DoubleToString(PipsToPrice(InpEntryDistancePips), g_digits),
               DoubleToString(PipsToPrice(InpStopLossPips), g_digits),
               DoubleToString(PipsToPrice(InpTakeProfitPips), g_digits),
               DoubleToString(PipsToPrice(InpTrailingStopPips), g_digits),
               DoubleToString(PipsToPrice(InpTrailingStartPips), g_digits),
               DoubleToString(PipsToPrice(InpTrailingStepPips), g_digits));
   PrintFormat("[MSS] Lot=%.2f | Toi da %d lenh | StopsLevel=%d FreezeLevel=%d | Spread hien tai=%d point (%.1f pip), toi da %.1f pip",
               CalcLots(), InpMaxPositions,
               (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_FREEZE_LEVEL),
               (int)spreadPts, (double)spreadPts * g_point / g_pip, InpMaxSpreadPips);

   EventSetMillisecondTimer(250);
   UpdatePanel(true);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeletePendingOnExit &&
      (reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_PROGRAM))
      DeleteAllPendings();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   Process();
   UpdatePanel(false);
  }

//+------------------------------------------------------------------+
//| Timer: thong ke + xu ly du phong khi it tick                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ulong now = GetTickCount64();
   if(!g_isTester && (now < g_lastProcessMs || now - g_lastProcessMs >= 1000))
      Process();
   if(g_showPanel)
     {
      if(g_lastStatsMs == 0 || now < g_lastStatsMs || now - g_lastStatsMs >= 2000)
        {
         UpdateDailyStats();
         g_lastStatsMs = now;
        }
      UpdatePanel(false);
     }
  }

//+------------------------------------------------------------------+
//| Phan ung ngay khi co lenh khop / dong (khong cho tick moi)       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == g_sym)
      Process();
  }
//+------------------------------------------------------------------+
