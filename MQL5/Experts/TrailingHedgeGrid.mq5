//+------------------------------------------------------------------+
//|                                          TrailingHedgeGrid.mq5   |
//|                                                                  |
//|  EA dung lai tu video quay man hinh MT5 tren dien thoai          |
//|  (XAUUSD M1, tai khoan hedging, lot co so 0.05, 06/11/2026).     |
//|                                                                  |
//|  Chien luoc gom 5 phan (so lieu = doc tu video):                 |
//|   1. MO CHU KY: mo cung luc BUY + SELL lot co so (0.05), dat     |
//|      BUY STOP tai Ask + 3.00 va SELL STOP tai Bid - 3.00.        |
//|   2. LENH CHO TRAILING: lenh cho bi gia bo xa hon 3.00 + 2.00    |
//|      thi keo ve cach gia 3.00. Lenh cho khop -> dat lenh cho moi |
//|      cung chieu cach gia 3.00.                                   |
//|   3. NHOI LENH THEO XU HUONG: gia di them 2.20 so voi lenh cung  |
//|      chieu moi nhat -> mo them lenh, lot = co so x 1.2^n         |
//|      (n = so lenh cung chieu dang mo):                           |
//|      0.06 0.07 0.09 0.10 0.12 0.15 0.18 0.21 0.26 0.31 0.37 0.45 |
//|   4. CHOT CA RO: lenh vao gan nhat lai >= 1.10 va ca ro dang lai |
//|      (hoac vua co lenh moi ma ca ro da lai du) -> xoa lenh cho,  |
//|      dong tat ca lenh cung luc.                                  |
//|   5. NGHI 30 GIAY roi bat dau chu ky moi.                        |
//|                                                                  |
//|  Khoang cach tinh bang DON VI GIA (XAUUSD: 1.00 = 1 USD/oz),     |
//|  dung dung cho moi san du bao gia 2 hay 3 so le. Ma khac: dung   |
//|  InpDistanceScale (EURUSD/GBPUSD 0.0001, USDJPY 0.01...).        |
//|                                                                  |
//|  YEU CAU: tai khoan HEDGING (giu Buy va Sell cung luc).          |
//+------------------------------------------------------------------+
#property copyright   "hoi1986"
#property version     "1.00"
#property description "Trailing Hedge Grid: cap Buy+Sell, Buy/Sell Stop trailing, nhoi lenh theo xu huong (lot x1.2), chot ca ro."
#property description "Mac dinh = thong so doc tu video (XAUUSD, lot 0.05, lenh cho 3.00/2.00, nhoi 2.20, TP 1.10, nghi 30 giay)."
#property description "Yeu cau tai khoan HEDGING. Tu thich ung so le, hau to symbol, kieu khop lenh, stops/freeze level, lot cua tung san."

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_SIZING
  {
   LOTS_FIXED      = 0, // Co dinh (giong video)
   LOTS_BY_BALANCE = 1  // Tu dong theo so du
  };

enum ENUM_LOT_ROUNDING
  {
   LOT_ROUND_NEAREST = 0, // Lam tron gan nhat (giong video: 0.0864 -> 0.09)
   LOT_ROUND_DOWN    = 1  // Lam tron xuong (it rui ro hon)
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== KHOI LUONG ==="
input ENUM_LOT_SIZING   InpLotSizing         = LOTS_FIXED;        // Cach tinh lot co so
input double            InpBaseLot           = 0.05;              // Lot co so (cap mo dau + lenh cho)
input double            InpBalancePerBaseLot = 100000.0;          // Che do tu dong: so du ung voi 1 lot co so
input double            InpLotMultiplier     = 1.20;              // He so nhoi: lot = co so x he so ^ n
input ENUM_LOT_ROUNDING InpLotRounding       = LOT_ROUND_NEAREST; // Cach lam tron lot nhoi
input double            InpMaxLot            = 0.0;               // Lot toi da cho 1 lenh (0 = khong gioi han)

input group "=== KHOANG CACH (don vi GIA, mac dinh cho XAUUSD) ==="
input double InpDistanceScale    = 1.0;  // He so quy doi cho ma khac (XAU 1, EURUSD 0.0001, USDJPY 0.01)
input double InpPendingDistance  = 3.00; // Lenh cho cach gia: Buy Stop = Ask + d, Sell Stop = Bid - d
input double InpPendingTrailStep = 2.00; // Buoc keo lenh cho (keo khi cach gia > d + buoc)
input double InpAddOnStep        = 2.20; // Buoc nhoi lenh so voi lenh cung chieu moi nhat
input double InpTakeProfit       = 1.10; // Chot ca ro khi lenh vao gan nhat lai bang khoang nay
input double InpEntryCloseDist   = 0.80; // Chot ngay khi vua co lenh moi ma ro lai >= khoang nay x gia tri lot co so (0 = tat)
input double InpMaxSlippage      = 0.50; // Truot gia toi da cho lenh thi truong

input group "=== CHU KY ==="
input bool   InpUsePendings      = true; // Dung cap Buy Stop / Sell Stop
input bool   InpUseAddOns        = true; // Nhoi lenh theo xu huong
input int    InpCooldownSec      = 30;   // Nghi giua 2 chu ky (giay)
input double InpMinBasketProfit  = 0.0;  // Ca ro phai lai hon muc nay moi chot TP (tien)
input int    InpMaxPositionsSide = 0;    // So lenh toi da moi chieu (0 = khong gioi han, giong video)
input double InpCommissionPerLot = 0.0;  // Phi giao dich 2 chieu cho 1 lot (tien) de tinh lai rong

input group "=== BO LOC KHI MO CHU KY MOI ==="
input double InpMaxSpreadStart = 0.0;   // Spread toi da de mo chu ky (don vi gia, 0 = tat)
input bool   InpUseTimeFilter  = false; // Bat bo loc gio (gio may chu)
input int    InpStartHour      = 1;     // Gio bat dau (0-23)
input int    InpStartMinute    = 5;     // Phut bat dau (0-59)
input int    InpEndHour        = 23;    // Gio ket thuc (0-23)
input int    InpEndMinute      = 50;    // Phut ket thuc (0-59)

input group "=== BAO VE TAI KHOAN (0 = tat) ==="
input double InpMaxBasketLoss     = 0.0; // Ro lo tha noi toi da (tien) -> dong het
input double InpMaxBasketLossPct  = 0.0; // Ro lo tha noi toi da (% so du) -> dong het
input int    InpPauseAfterStopMin = 60;  // Nghi bao nhieu phut sau khi cat lo ro
input double InpDailyLossPct      = 0.0; // Lo toi da trong ngay (% so du dau ngay) -> dong het, nghi den ngay moi
input double InpDailyTargetPct    = 0.0; // Muc tieu lai trong ngay (%) -> khong mo chu ky moi den ngay moi

input group "=== KHAC ==="
input ulong  InpMagic               = 20261106; // Magic number
input string InpOrderComment        = "THG";    // Ghi chu lenh
input bool   InpAsyncClose          = true;     // Dong ca ro bang lenh bat dong bo (nhanh, cung mot gia)
input bool   InpDeletePendingOnExit = true;     // Xoa lenh cho khi go EA khoi bieu do
input bool   InpShowPanel           = true;     // Hien bang thong tin tren bieu do
input bool   InpDrawLevels          = true;     // Ve muc TP / muc nhoi lenh tren bieu do

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define EA_NAME   "Trailing Hedge Grid v1.00"
#define OBJ_PREF  "THG_"

//--- symbol
string   g_sym        = "";
int      g_digits     = 0;
double   g_point      = 0.0;
double   g_tick       = 0.0;
bool     g_isTester   = false;
bool     g_showPanel  = true;
bool     g_stopOrdersOk = true;

//--- khoang cach da quy doi (don vi gia)
double   g_dist       = 0.0;   // lenh cho cach gia
double   g_trailStep  = 0.0;   // buoc keo lenh cho
double   g_addStep    = 0.0;   // buoc nhoi
double   g_tp         = 0.0;   // TP cua lenh vao gan nhat
double   g_entryClose = 0.0;   // nguong chot ngay sau lenh moi
double   g_maxSpread  = 0.0;
double   g_slip       = 0.0;

//--- kieu khop lenh / het han (tu do theo san)
ENUM_ORDER_TYPE_FILLING g_fillPending   = ORDER_FILLING_RETURN;
ENUM_ORDER_TYPE_FILLING g_fillMarket    = ORDER_FILLING_FOK;
bool                    g_fillPendingOk = false;
bool                    g_fillMarketOk  = false;
ENUM_ORDER_TYPE_TIME    g_typeTime      = ORDER_TIME_GTC;

//--- dong ho
ulong    g_nowMs         = 0;  // gio may chu (ms), tang dan
ulong    g_entryBlockClk = 0;  // tam khoa vao lenh / dat lenh cho den moc nay (ClockMs)
ulong    g_mgmtBlockClk  = 0;  // tam khoa sua / dong lenh den moc nay (ClockMs)
ulong    g_lastProcessClk = 0;
ulong    g_lastPanelClk  = 0;
ulong    g_lastStatsClk  = 0;
ulong    g_lastErrClk    = 0;
uint     g_lastErrCode   = 0;

//--- trang thai chu ky
bool     g_hadBasket      = false;
ulong    g_lastEntryMsc   = 0;  // thoi diem mo cua lenh moi nhat da biet
ulong    g_lastCloseMs    = 0;  // gio may chu luc ro gan nhat dong xong
ulong    g_startUntilMs   = 0;  // han hoan tat cap mo dau
ulong    g_startRetryClk  = 0;
ulong    g_addBlockBuyClk = 0;
ulong    g_addBlockSellClk = 0;
ulong    g_bsBlockClk     = 0;
ulong    g_ssBlockClk     = 0;
ulong    g_pauseUntilMs   = 0;
bool     g_closing        = false;
string   g_closeReason    = "";
ulong    g_closeStartMs   = 0;
ulong    g_lastCloseSendClk = 0;
int      g_closeCount     = 0;
double   g_closeLots      = 0.0;
int      g_cycleNo        = 0;
string   g_status         = "Khoi dong";
bool     g_busy           = false;

//--- bao ve trong ngay
datetime g_dayStart      = 0;
double   g_dayStartBal   = 0.0;
bool     g_dayHalted     = false;
bool     g_dayTargetHit  = false;

//--- thong ke trong ngay (chi lenh cua EA nay)
int      g_dTrades = 0;
double   g_dProfit = 0.0;
double   g_dComm   = 0.0;
double   g_dSwap   = 0.0;
int      g_dBaskets = 0;

//+------------------------------------------------------------------+
//| Thong tin ca ro                                                  |
//+------------------------------------------------------------------+
struct SBasket
  {
   int      nBuy;
   int      nSell;
   double   lotsBuy;
   double   lotsSell;
   double   profit;        // lai/lo tha noi (profit + swap - phi uoc tinh)
   ulong    lastMsc;       // thoi diem mo cua lenh moi nhat
   ulong    lastTicket;
   bool     lastIsBuy;
   double   lastOpen;
   double   lastLots;
   ulong    lastBuyMsc;
   ulong    lastBuyTicket;
   double   lastBuyOpen;
   ulong    lastSellMsc;
   ulong    lastSellTicket;
   double   lastSellOpen;
  };

//+------------------------------------------------------------------+
//| Helpers: gia, thoi gian, quyen so huu                            |
//+------------------------------------------------------------------+
double NormUp(const double price)
  {
   return NormalizeDouble(MathCeil(price / g_tick - 1e-7) * g_tick, g_digits);
  }

double NormDown(const double price)
  {
   return NormalizeDouble(MathFloor(price / g_tick + 1e-7) * g_tick, g_digits);
  }

string Px(const double price) { return DoubleToString(price, g_digits); }

double StopsLevelDist()  { return (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL)  * g_point; }
double FreezeLevelDist() { return (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_FREEZE_LEVEL) * g_point; }

//--- dong ho dung de gian cach thao tac: thoi gian thuc khi chay that, thoi gian mo phong khi test
ulong ClockMs()
  {
   if(g_isTester)
      return g_nowMs;
   return GetTickCount64();
  }

//--- gio may chu (ms), khong bao gio giam
void UpdateNow(const MqlTick &tk)
  {
   ulong t = (ulong)TimeTradeServer() * 1000;
   ulong k = (tk.time_msc > 0) ? (ulong)tk.time_msc : (ulong)tk.time * 1000;
   if(k > t)
      t = k;
   if(t > g_nowMs)
      g_nowMs = t;
  }

bool IsOwn(const string sym, const long magic)
  {
   return (sym == g_sym && (ulong)magic == InpMagic);
  }

bool IsDone(const uint rc)
  {
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
  }

ulong SlippagePoints()
  {
   double pts = MathRound(g_slip / g_point);
   if(pts < 0.0)
      pts = 0.0;
   return (ulong)pts;
  }

//--- so tien lai/lo cua 1 lot khi gia di 1.0 don vi
double ValuePerPriceUnit()
  {
   double tv = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0)
      return 0.0;
   return tv / ts;
  }

//--- chieu giao dich san cho phep
bool SideAllowed(const bool isBuy)
  {
   ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(g_sym, SYMBOL_TRADE_MODE);
   if(tm == SYMBOL_TRADE_MODE_FULL)
      return true;
   if(isBuy)
      return (tm == SYMBOL_TRADE_MODE_LONGONLY);
   return (tm == SYMBOL_TRADE_MODE_SHORTONLY);
  }

//+------------------------------------------------------------------+
//| Khoi luong                                                       |
//+------------------------------------------------------------------+
double NormalizeLots(double lots, const bool nearest)
  {
   double vmin  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      vstep = (vmin > 0.0 ? vmin : 0.01);
   double k = lots / vstep;
   k = nearest ? MathRound(k) : MathFloor(k + 1e-7);
   lots = k * vstep;
   if(InpMaxLot > 0.0 && lots > InpMaxLot)
      lots = MathFloor(InpMaxLot / vstep + 1e-7) * vstep;
   if(lots < vmin)
      lots = vmin;
   if(vmax > 0.0 && lots > vmax)
      lots = vmax;
   int vd = (int)MathMax(0.0, MathCeil(-MathLog10(vstep) - 1e-9));
   return NormalizeDouble(lots, vd);
  }

double BaseLot()
  {
   double lots = InpBaseLot;
   if(InpLotSizing == LOTS_BY_BALANCE && InpBalancePerBaseLot > 0.0)
      lots = InpBaseLot * AccountInfoDouble(ACCOUNT_BALANCE) / InpBalancePerBaseLot;
   return NormalizeLots(lots, false);
  }

//--- lot cua lenh nhoi khi dang co n lenh cung chieu
double AddOnLots(const int n)
  {
   double lots = BaseLot() * MathPow(InpLotMultiplier, (double)n);
   return NormalizeLots(lots, InpLotRounding == LOT_ROUND_NEAREST);
  }

bool MarginOk(const ENUM_ORDER_TYPE type, const double lots, const double price)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(type, g_sym, lots, price, margin))
      return true; // khong tinh duoc -> de may chu quyet dinh
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin * 1.1);
  }

//--- nguong lai (tien) de chot ngay sau khi co lenh moi
double EntryCloseMoney()
  {
   if(g_entryClose <= 0.0)
      return 0.0;
   return g_entryClose * BaseLot() * ValuePerPriceUnit();
  }

//--- muc lo toi da cua ro (tien), 0 = tat
double BasketLossLimit()
  {
   double lim = 0.0;
   if(InpMaxBasketLoss > 0.0)
      lim = InpMaxBasketLoss;
   if(InpMaxBasketLossPct > 0.0)
     {
      double p = AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxBasketLossPct / 100.0;
      lim = (lim > 0.0) ? MathMin(lim, p) : p;
     }
   return lim;
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
//| Gui lenh, tu thu cac kieu khop lenh (FOK/IOC/RETURN)             |
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

int FillCandidates(ENUM_ORDER_TYPE_FILLING &cand[], const bool isPending)
  {
   int n = 0;
   if(isPending && g_fillPendingOk)
      AddFill(cand, n, g_fillPending);
   if(!isPending && g_fillMarketOk)
      AddFill(cand, n, g_fillMarket);
   long flags = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if(isPending)
      AddFill(cand, n, ORDER_FILLING_RETURN);
   if((flags & SYMBOL_FILLING_FOK) != 0)
      AddFill(cand, n, ORDER_FILLING_FOK);
   if((flags & SYMBOL_FILLING_IOC) != 0)
      AddFill(cand, n, ORDER_FILLING_IOC);
   AddFill(cand, n, ORDER_FILLING_RETURN);
   AddFill(cand, n, ORDER_FILLING_FOK);
   AddFill(cand, n, ORDER_FILLING_IOC);
   return n;
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
   int n = FillCandidates(cand, isPending);
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
         wait = 300;
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

   ulong until = ClockMs() + wait;
   if(entry)
     {
      if(until > g_entryBlockClk)
         g_entryBlockClk = until;
     }
   else
     {
      if(until > g_mgmtBlockClk)
         g_mgmtBlockClk = until;
     }

   ulong now = ClockMs();
   if(rc != g_lastErrCode || now < g_lastErrClk || now - g_lastErrClk >= 5000)
     {
      PrintFormat("[THG] %s that bai: retcode=%u (%s), loi=%d", what, rc, res.comment, GetLastError());
      g_lastErrCode = rc;
      g_lastErrClk  = now;
     }
  }

//+------------------------------------------------------------------+
//| Cac lenh giao dich co ban                                        |
//+------------------------------------------------------------------+
bool OpenMarket(const ENUM_ORDER_TYPE type, double lots, const string tag)
  {
   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk))
      return false;
   lots = NormalizeLots(lots, true);
   double price = (type == ORDER_TYPE_BUY) ? tk.ask : tk.bid;
   if(!MarginOk(type, lots, price))
     {
      PrintFormat("[THG] Khong du ky quy de mo %s %.2f lot -> tam dung vao lenh",
                  (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots);
      g_entryBlockClk = ClockMs() + 15000;
      return false;
     }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.magic     = InpMagic;
   req.volume    = lots;
   req.type      = type;
   req.price     = price;
   req.deviation = SlippagePoints();
   req.comment   = InpOrderComment + " " + tag;
   if(SendRequest(req, res, true, false))
     {
      PrintFormat("[THG] %s %s %.2f lot @ %s", tag, (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  lots, Px(res.price > 0.0 ? res.price : price));
      return true;
     }
   OnTradeFail("Mo lenh " + tag + (type == ORDER_TYPE_BUY ? " BUY" : " SELL"), res, true);
   return false;
  }

bool PlacePending(const ENUM_ORDER_TYPE type, const double price, const double lots)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action     = TRADE_ACTION_PENDING;
   req.symbol     = g_sym;
   req.magic      = InpMagic;
   req.volume     = lots;
   req.type       = type;
   req.price      = price;
   req.deviation  = SlippagePoints();
   req.type_time  = g_typeTime;
   req.expiration = ExpirationTime();
   req.comment    = InpOrderComment + " stop";
   if(SendRequest(req, res, true, true))
      return true;
   OnTradeFail(type == ORDER_TYPE_BUY_STOP ? "Dat Buy Stop" : "Dat Sell Stop", res, true);
   return false;
  }

bool ModifyPending(const ulong ticket, const double price)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action     = TRADE_ACTION_MODIFY;
   req.order      = ticket;
   req.symbol     = g_sym;
   req.magic      = InpMagic;
   req.price      = price;
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
   OnTradeFail("Xoa lenh cho", res, false);
   return false;
  }

bool ClosePositionReq(const ulong ticket, const bool isBuy, const double volume, const bool useAsync)
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
   req.comment   = InpOrderComment + " close";
   req.type      = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = isBuy ? tk.bid : tk.ask;

//--- bat dong bo: gui tat ca lenh dong gan nhu cung luc (giong video: ca ro dong cung 1 gia)
   if(useAsync && g_fillMarketOk)
     {
      req.type_filling = g_fillMarket;
      ZeroMemory(res);
      if(OrderSendAsync(req, res))
         return true;
     }
   if(SendRequest(req, res, true, false))
      return true;
   OnTradeFail("Dong lenh", res, false);
   return false;
  }

//+------------------------------------------------------------------+
//| Quet ca ro: dem lenh, lai/lo, lenh moi nhat                      |
//+------------------------------------------------------------------+
void ScanBasket(SBasket &b)
  {
   ZeroMemory(b);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
         continue;
      bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      ulong  msc   = (ulong)PositionGetInteger(POSITION_TIME_MSC);
      b.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(isBuy)
        {
         b.nBuy++;
         b.lotsBuy += vol;
         if(msc > b.lastBuyMsc || (msc == b.lastBuyMsc && ticket > b.lastBuyTicket))
           {
            b.lastBuyMsc    = msc;
            b.lastBuyTicket = ticket;
            b.lastBuyOpen   = open;
           }
        }
      else
        {
         b.nSell++;
         b.lotsSell += vol;
         if(msc > b.lastSellMsc || (msc == b.lastSellMsc && ticket > b.lastSellTicket))
           {
            b.lastSellMsc    = msc;
            b.lastSellTicket = ticket;
            b.lastSellOpen   = open;
           }
        }
      if(msc > b.lastMsc || (msc == b.lastMsc && ticket > b.lastTicket))
        {
         b.lastMsc    = msc;
         b.lastTicket = ticket;
         b.lastIsBuy  = isBuy;
         b.lastOpen   = open;
         b.lastLots   = vol;
        }
     }
   b.profit -= InpCommissionPerLot * (b.lotsBuy + b.lotsSell);
  }

//--- tim lenh cho cua EA (chi giu 1 Buy Stop + 1 Sell Stop)
void FindPendings(ulong &bsTicket, double &bsPrice, ulong &ssTicket, double &ssPrice, const bool deleteDup)
  {
   bsTicket = 0;
   ssTicket = 0;
   bsPrice  = 0.0;
   ssPrice  = 0.0;
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
            if(deleteDup)
               DeletePending(ticket);
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
               if(deleteDup)
                  DeletePending(ticket);
           }
     }
  }

int CountOwnPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(IsOwn(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
         n++;
     }
   return n;
  }

void DeleteAllPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
         continue;
      DeletePending(ticket);
     }
  }

void SendCloseAll()
  {
   bool useAsync = InpAsyncClose && !g_isTester;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!IsOwn(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
         continue;
      bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      ClosePositionReq(ticket, isBuy, PositionGetDouble(POSITION_VOLUME), useAsync);
     }
  }

//+------------------------------------------------------------------+
//| Lai/lo da chot cua cac lenh dong tu moc thoi gian (ms)           |
//+------------------------------------------------------------------+
double RealizedSince(const ulong fromMs)
  {
   datetime from = (datetime)(fromMs / 1000) - 10;
   if(!HistorySelect(from, TimeCurrent() + 3600))
      return 0.0;
   double sum   = 0.0;
   int    total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(!IsOwn(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
         continue;
      ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY && e != DEAL_ENTRY_INOUT)
         continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_TIME_MSC) + 5000 < fromMs)
         continue;
      sum += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
             HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   return sum;
  }

//--- moc thoi gian dong lenh gan nhat cua EA (de giu dung thoi gian nghi khi khoi dong lai)
void InitLastClose()
  {
   g_lastCloseMs = 0;
   datetime now = TimeCurrent();
   if(now <= 0)
      return;
   if(!HistorySelect(now - 3 * 86400, now + 3600))
      return;
   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(!IsOwn(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
         continue;
      ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY && e != DEAL_ENTRY_INOUT)
         continue;
      ulong t = (ulong)HistoryDealGetInteger(d, DEAL_TIME_MSC);
      if(t > g_lastCloseMs)
         g_lastCloseMs = t;
     }
  }

//+------------------------------------------------------------------+
//| Dong ca ro                                                       |
//+------------------------------------------------------------------+
void FinishBasket()
  {
   g_closing      = false;
   g_hadBasket    = false;
   g_lastCloseMs  = g_nowMs;
   g_startUntilMs = 0;
   g_dBaskets++;
   double realized = RealizedSince(g_closeStartMs);
   PrintFormat("[THG] Da dong xong ro #%d (%s): %d lenh / %.2f lot, lai/lo dong lenh = %.2f %s. Nghi %d giay.",
               g_cycleNo, g_closeReason, g_closeCount, g_closeLots, realized,
               AccountInfoString(ACCOUNT_CURRENCY), InpCooldownSec);
   g_lastStatsClk = 0;
  }

void ProcessClosing(const SBasket &b)
  {
   if(CountOwnPendings() > 0)
      DeleteAllPendings();
   if(b.nBuy + b.nSell == 0)
     {
      FinishBasket();
      return;
     }
   ulong clk = ClockMs();
   if(clk < g_mgmtBlockClk)
      return;
   if(g_lastCloseSendClk == 0 || clk < g_lastCloseSendClk || clk - g_lastCloseSendClk >= 1500)
     {
      SendCloseAll();
      g_lastCloseSendClk = clk;
     }
  }

void BeginCloseAll(const string reason, const SBasket &b)
  {
   g_closing          = true;
   g_closeReason      = reason;
   g_closeStartMs     = g_nowMs;
   g_closeCount       = b.nBuy + b.nSell;
   g_closeLots        = b.lotsBuy + b.lotsSell;
   g_lastCloseSendClk = 0;
   PrintFormat("[THG] CHOT CA RO #%d: %s | Buy %d (%.2f lot) / Sell %d (%.2f lot) | lai tha noi %.2f",
               g_cycleNo, reason, b.nBuy, b.lotsBuy, b.nSell, b.lotsSell, b.profit);
//--- giong video: xoa lenh cho truoc, sau do dong tat ca lenh
   ProcessClosing(b);
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
//| Bo loc mo chu ky moi                                             |
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

bool StartFiltersOk(const MqlTick &tk, string &why)
  {
   if(g_dayHalted)
     {
      why = "Da cham muc lo trong ngay -> nghi den ngay moi";
      return false;
     }
   if(g_dayTargetHit)
     {
      why = "Da dat muc tieu lai trong ngay -> nghi den ngay moi";
      return false;
     }
   if(g_nowMs < g_pauseUntilMs)
     {
      why = StringFormat("Dang nghi sau khi cat lo ro (con %d phut)",
                         (int)((g_pauseUntilMs - g_nowMs) / 60000 + 1));
      return false;
     }
   double spread = tk.ask - tk.bid;
   if(g_maxSpread > 0.0 && spread > g_maxSpread + g_tick * 0.5)
     {
      why = StringFormat("Spread %s > %s -> cho spread giam", Px(spread), Px(g_maxSpread));
      return false;
     }
   if(!InTradingTime())
     {
      why = "Ngoai khung gio giao dich";
      return false;
     }
   if(!SideAllowed(true) || !SideAllowed(false))
     {
      why = "San chi cho 1 chieu / chi dong lenh tren ma nay -> khong the hedge";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Gioi han lai/lo trong ngay (luu qua Global Variables)            |
//+------------------------------------------------------------------+
string GvName(const string key)
  {
   return "THG_" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "_" + (string)InpMagic + "_" + key;
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

   string gd = GvName("D"), gb = GvName("B"), gh = GvName("H"), gt = GvName("T");
   if(GlobalVariableCheck(gd) && (datetime)(long)GlobalVariableGet(gd) == ds && GlobalVariableCheck(gb))
     {
      g_dayStartBal  = GlobalVariableGet(gb);
      g_dayHalted    = (GlobalVariableCheck(gh) && GlobalVariableGet(gh) > 0.5);
      g_dayTargetHit = (GlobalVariableCheck(gt) && GlobalVariableGet(gt) > 0.5);
     }
   else
     {
      g_dayStartBal  = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dayHalted    = false;
      g_dayTargetHit = false;
      GlobalVariableSet(gd, (double)ds);
      GlobalVariableSet(gb, g_dayStartBal);
      GlobalVariableSet(gh, 0.0);
      GlobalVariableSet(gt, 0.0);
     }
   g_dBaskets     = 0;
   g_lastStatsClk = 0;
  }

//--- tra ve true neu phai dong het ngay (cham muc lo ngay)
bool CheckDailyGuard()
  {
   if(InpDailyLossPct <= 0.0 && InpDailyTargetPct <= 0.0)
      return false;
   if(g_dayStartBal <= 0.0)
      return false;
   double pnl = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBal;
   if(!g_dayHalted && InpDailyLossPct > 0.0 && pnl <= -g_dayStartBal * InpDailyLossPct / 100.0)
     {
      g_dayHalted = true;
      GlobalVariableSet(GvName("H"), 1.0);
      PrintFormat("[THG] Lo trong ngay %.2f (>= %.2f%%) -> dong het, nghi den ngay moi.", pnl, InpDailyLossPct);
      return true;
     }
   if(!g_dayTargetHit && InpDailyTargetPct > 0.0 && pnl >= g_dayStartBal * InpDailyTargetPct / 100.0)
     {
      g_dayTargetHit = true;
      GlobalVariableSet(GvName("T"), 1.0);
      PrintFormat("[THG] Dat muc tieu ngay %.2f (>= %.2f%%) -> khong mo chu ky moi den ngay moi.", pnl, InpDailyTargetPct);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cap lenh cho Buy Stop / Sell Stop co trailing                    |
//+------------------------------------------------------------------+
double PendingDistance()
  {
   double d     = g_dist;
   double stops = StopsLevelDist();
   if(stops > 0.0 && d < stops + g_tick)
      d = stops + g_tick;
   if(d < g_tick)
      d = g_tick;
   return d;
  }

void ManagePendings(const MqlTick &tk, const SBasket &b)
  {
   ulong  bsTicket = 0, ssTicket = 0;
   double bsPrice  = 0.0, ssPrice = 0.0;
   FindPendings(bsTicket, bsPrice, ssTicket, ssPrice, true);

   bool wantBuy  = InpUsePendings && g_stopOrdersOk && SideAllowed(true) &&
                   (InpMaxPositionsSide <= 0 || b.nBuy < InpMaxPositionsSide);
   bool wantSell = InpUsePendings && g_stopOrdersOk && SideAllowed(false) &&
                   (InpMaxPositionsSide <= 0 || b.nSell < InpMaxPositionsSide);

   if(!wantBuy && bsTicket > 0)
      DeletePending(bsTicket);
   if(!wantSell && ssTicket > 0)
      DeletePending(ssTicket);

   ulong  clk    = ClockMs();
   if(clk < g_entryBlockClk)
      return;
   double dist   = PendingDistance();
   double trail  = dist + g_trailStep;     // video: keo khi cach gia > 3.00 + 2.00
   double freeze = FreezeLevelDist();
   double half   = g_tick * 0.5;
   double lots   = BaseLot();

//--- BUY STOP: dat moi neu chua co (vua khop / moi mo chu ky), keo xuong khi gia giam xa
   if(wantBuy)
     {
      double want = NormUp(tk.ask + dist);
      if(bsTicket == 0)
        {
         if(clk >= g_bsBlockClk && MarginOk(ORDER_TYPE_BUY, lots, want))
           {
            if(PlacePending(ORDER_TYPE_BUY_STOP, want, lots))
               PrintFormat("[THG] Dat BUY STOP %.2f @ %s (Ask %s + %s)", lots, Px(want), Px(tk.ask), Px(dist));
            g_bsBlockClk = clk + 1000;
           }
        }
      else
         if(bsPrice - tk.ask > trail + half && bsPrice - tk.ask > freeze && MathAbs(bsPrice - want) >= g_tick)
           {
            if(ModifyPending(bsTicket, want))
               PrintFormat("[THG] Keo BUY STOP %s -> %s", Px(bsPrice), Px(want));
           }
     }

//--- SELL STOP: dat moi neu chua co, keo len khi gia tang xa
   if(wantSell && ClockMs() >= g_entryBlockClk)
     {
      double want = NormDown(tk.bid - dist);
      if(ssTicket == 0)
        {
         if(clk >= g_ssBlockClk && MarginOk(ORDER_TYPE_SELL, lots, want))
           {
            if(PlacePending(ORDER_TYPE_SELL_STOP, want, lots))
               PrintFormat("[THG] Dat SELL STOP %.2f @ %s (Bid %s - %s)", lots, Px(want), Px(tk.bid), Px(dist));
            g_ssBlockClk = clk + 1000;
           }
        }
      else
         if(tk.bid - ssPrice > trail + half && tk.bid - ssPrice > freeze && MathAbs(ssPrice - want) >= g_tick)
           {
            if(ModifyPending(ssTicket, want))
               PrintFormat("[THG] Keo SELL STOP %s -> %s", Px(ssPrice), Px(want));
           }
     }
  }

//+------------------------------------------------------------------+
//| Nhoi lenh theo xu huong                                          |
//+------------------------------------------------------------------+
void ManageAddOns(const MqlTick &tk, const SBasket &b)
  {
   ulong  clk  = ClockMs();
   double half = g_tick * 0.5;
   if(clk < g_entryBlockClk)
      return;

//--- BUY: Ask vuot lenh BUY moi nhat them 1 buoc
   if(b.nBuy > 0 && clk >= g_addBlockBuyClk && SideAllowed(true) &&
      (InpMaxPositionsSide <= 0 || b.nBuy < InpMaxPositionsSide) &&
      tk.ask >= b.lastBuyOpen + g_addStep - half)
     {
      double lots = AddOnLots(b.nBuy);
      PrintFormat("[THG] Nhoi BUY: Ask %s >= lenh BUY moi nhat %s + %s -> lot %.2f (lenh BUY thu %d)",
                  Px(tk.ask), Px(b.lastBuyOpen), Px(g_addStep), lots, b.nBuy + 1);
      OpenMarket(ORDER_TYPE_BUY, lots, "add");
      g_addBlockBuyClk = clk + 1500;
     }

//--- SELL: Bid thung lenh SELL moi nhat them 1 buoc
   if(b.nSell > 0 && ClockMs() >= g_entryBlockClk && clk >= g_addBlockSellClk && SideAllowed(false) &&
      (InpMaxPositionsSide <= 0 || b.nSell < InpMaxPositionsSide) &&
      tk.bid <= b.lastSellOpen - g_addStep + half)
     {
      double lots = AddOnLots(b.nSell);
      PrintFormat("[THG] Nhoi SELL: Bid %s <= lenh SELL moi nhat %s - %s -> lot %.2f (lenh SELL thu %d)",
                  Px(tk.bid), Px(b.lastSellOpen), Px(g_addStep), lots, b.nSell + 1);
      OpenMarket(ORDER_TYPE_SELL, lots, "add");
      g_addBlockSellClk = clk + 1500;
     }
  }

//+------------------------------------------------------------------+
//| Cap mo dau: neu 1 chan bi loi thi thu lai trong vai giay         |
//+------------------------------------------------------------------+
void CompleteStartPair(const SBasket &b)
  {
   if(g_startUntilMs == 0)
      return;
   if(g_nowMs >= g_startUntilMs || (b.nBuy > 0 && b.nSell > 0))
     {
      g_startUntilMs = 0;
      return;
     }
   ulong clk = ClockMs();
   if(clk < g_startRetryClk || clk < g_entryBlockClk)
      return;
   g_startRetryClk = clk + 1500;
   if(b.nBuy == 0 && SideAllowed(true))
      OpenMarket(ORDER_TYPE_BUY, BaseLot(), "start");
   else
      if(b.nSell == 0 && SideAllowed(false))
         OpenMarket(ORDER_TYPE_SELL, BaseLot(), "start");
  }

//+------------------------------------------------------------------+
//| Mo chu ky moi: BUY + SELL lot co so                              |
//+------------------------------------------------------------------+
void TryStartCycle(const MqlTick &tk)
  {
   ulong clk = ClockMs();
   if(clk < g_startRetryClk || clk < g_entryBlockClk)
     {
      g_status = "Dang cho san xu ly lenh...";
      return;
     }
   ulong cool = (ulong)MathMax(0, InpCooldownSec) * 1000;
   if(g_lastCloseMs > 0 && g_nowMs < g_lastCloseMs + cool)
     {
      g_status = StringFormat("Nghi giua 2 chu ky: con %d giay", (int)((g_lastCloseMs + cool - g_nowMs + 999) / 1000));
      return;
     }
   string why = "";
   if(!StartFiltersOk(tk, why))
     {
      g_status = why;
      return;
     }
   double lot = BaseLot();
   if(!MarginOk(ORDER_TYPE_BUY, lot, tk.ask) || !MarginOk(ORDER_TYPE_SELL, lot, tk.bid))
     {
      g_status = "Khong du ky quy de mo chu ky moi";
      g_startRetryClk = clk + 15000;
      return;
     }

   g_cycleNo++;
   g_startRetryClk = clk + 3000;            // tranh mo trung khi lenh chua kip hien trong danh sach
   g_startUntilMs  = g_nowMs + 10000;       // 10 giay de hoan tat ca 2 chan
   PrintFormat("[THG] ===== Chu ky #%d: mo cap BUY + SELL %.2f lot (Bid %s / Ask %s) =====",
               g_cycleNo, lot, Px(tk.bid), Px(tk.ask));
   OpenMarket(ORDER_TYPE_BUY, lot, "start");
   OpenMarket(ORDER_TYPE_SELL, lot, "start");

//--- dat luon cap lenh cho neu cac lenh da hien trong danh sach
   MqlTick tk2;
   if(SymbolInfoTick(g_sym, tk2))
     {
      SBasket b;
      ScanBasket(b);
      if(b.nBuy + b.nSell > 0)
        {
         g_hadBasket = true;
         if(b.lastMsc > g_lastEntryMsc)
            g_lastEntryMsc = b.lastMsc;
         ManagePendings(tk2, b);
        }
     }
   g_status = "Da mo chu ky moi";
  }

//+------------------------------------------------------------------+
//| Quan ly ca ro dang chay                                          |
//+------------------------------------------------------------------+
void ManageBasket(const MqlTick &tk, const SBasket &b, const bool newEntry)
  {
   double half = g_tick * 0.5;

//--- 1) bao ve: ro lo qua muc cho phep
   double lossLimit = BasketLossLimit();
   if(lossLimit > 0.0 && b.profit <= -lossLimit)
     {
      g_pauseUntilMs = g_nowMs + (ulong)MathMax(0, InpPauseAfterStopMin) * 60000;
      BeginCloseAll(StringFormat("CAT LO ro %.2f (gioi han %.2f)", b.profit, lossLimit), b);
      return;
     }

//--- 2) vua co lenh moi (khop lenh cho / nhoi) ma ca ro da lai du -> chot ngay
   double ecMoney = EntryCloseMoney();
   if(newEntry && ecMoney > 0.0 && b.profit >= ecMoney)
     {
      BeginCloseAll(StringFormat("ro lai %.2f >= %.2f ngay sau lenh moi", b.profit, ecMoney), b);
      return;
     }

//--- 3) TP: lenh vao gan nhat da lai >= TP va ca ro dang lai
   if(b.lastTicket > 0)
     {
      bool hit = b.lastIsBuy ? (tk.bid >= b.lastOpen + g_tp - half)
                             : (tk.ask <= b.lastOpen - g_tp + half);
      if(hit && b.profit > InpMinBasketProfit)
        {
         BeginCloseAll(StringFormat("TP: lenh %s moi nhat @ %s da lai %s, ca ro lai %.2f",
                                    (b.lastIsBuy ? "BUY" : "SELL"), Px(b.lastOpen), Px(g_tp), b.profit), b);
         return;
        }
     }

//--- 4) hoan tat cap mo dau neu 1 chan loi
   CompleteStartPair(b);

//--- 5) nhoi lenh theo xu huong
   if(InpUseAddOns)
      ManageAddOns(tk, b);

//--- 6) cap lenh cho trailing
   ManagePendings(tk, b);
  }

//+------------------------------------------------------------------+
//| Ve muc TP / muc nhoi tren bieu do                                |
//+------------------------------------------------------------------+
void SetHLine(const string name, const double price, const color clr, const string text)
  {
   string obj = OBJ_PREF + name;
   if(price <= 0.0)
     {
      if(ObjectFind(0, obj) >= 0)
         ObjectDelete(0, obj);
      return;
     }
   if(ObjectFind(0, obj) < 0)
     {
      if(!ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price))
         return;
      ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, obj, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, obj, OBJPROP_BACK, true);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetDouble(0, obj, OBJPROP_PRICE, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_TOOLTIP, text);
  }

void DrawLevels(const SBasket &b)
  {
   if(!InpDrawLevels || (g_isTester && MQLInfoInteger(MQL_VISUAL_MODE) == 0))
      return;
   bool active = (b.nBuy + b.nSell > 0);
   double tp = 0.0, nb = 0.0, ns = 0.0;
   if(active && b.lastTicket > 0)
      tp = b.lastIsBuy ? b.lastOpen + g_tp : b.lastOpen - g_tp;
   if(active && InpUseAddOns && b.nBuy > 0)
      nb = b.lastBuyOpen + g_addStep;
   if(active && InpUseAddOns && b.nSell > 0)
      ns = b.lastSellOpen - g_addStep;
   SetHLine("TP", tp, clrGold, "THG: muc TP ca ro (lenh moi nhat +/- " + Px(g_tp) + ")");
   SetHLine("ADDB", nb, clrDodgerBlue, StringFormat("THG: nhoi BUY %.2f lot", AddOnLots(b.nBuy)));
   SetHLine("ADDS", ns, clrTomato, StringFormat("THG: nhoi SELL %.2f lot", AddOnLots(b.nSell)));
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
   if(g_dayStart <= 0)
      return;
   if(!HistorySelect(g_dayStart, TimeCurrent() + 86400))
      return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(!IsOwn(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         g_dTrades++;
      g_dProfit += HistoryDealGetDouble(d, DEAL_PROFIT);
      g_dComm   += HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      g_dSwap   += HistoryDealGetDouble(d, DEAL_SWAP);
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
   if(!force && now >= g_lastPanelClk && now - g_lastPanelClk < 500)
      return;
   g_lastPanelClk = now;

   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk))
      return;
   SBasket b;
   ScanBasket(b);
   ulong  bsT = 0, ssT = 0;
   double bsP = 0.0, ssP = 0.0;
   FindPendings(bsT, bsP, ssT, ssP, false);
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   int    n   = b.nBuy + b.nSell;

   string s = EA_NAME + "\n";
   s += StringFormat("%s | Magic %s | Spread %s | Lot co so %.2f x%.2f\n",
                     g_sym, (string)InpMagic, Px(tk.ask - tk.bid), BaseLot(), InpLotMultiplier);
   s += StringFormat("Lenh cho %s (keo khi > %s) | Nhoi %s | TP %s | Nghi %ds\n",
                     Px(g_dist), Px(g_dist + g_trailStep), Px(g_addStep), Px(g_tp), InpCooldownSec);
   if(n > 0)
     {
      s += StringFormat("Ro #%d: Buy %d (%.2f lot) | Sell %d (%.2f lot) | Lai/lo %.2f %s\n",
                        g_cycleNo, b.nBuy, b.lotsBuy, b.nSell, b.lotsSell, b.profit, cur);
      s += StringFormat("Lenh moi nhat: %s %.2f @ %s -> TP %s\n",
                        (b.lastIsBuy ? "BUY" : "SELL"), b.lastLots, Px(b.lastOpen),
                        Px(b.lastIsBuy ? b.lastOpen + g_tp : b.lastOpen - g_tp));
      string nb = (b.nBuy > 0) ? StringFormat("BUY %.2f khi Ask >= %s", AddOnLots(b.nBuy), Px(b.lastBuyOpen + g_addStep)) : "-";
      string ns = (b.nSell > 0) ? StringFormat("SELL %.2f khi Bid <= %s", AddOnLots(b.nSell), Px(b.lastSellOpen - g_addStep)) : "-";
      s += "Nhoi tiep: " + nb + " | " + ns + "\n";
     }
   else
      s += "Chua co lenh\n";
   s += StringFormat("Lenh cho: BuyStop %s | SellStop %s\n",
                     (bsT > 0 ? Px(bsP) : "-"), (ssT > 0 ? Px(ssP) : "-"));
   s += StringFormat("Hom nay: %d ro | %d lenh | Lai gop %.2f | Phi %.2f | Swap %.2f | RONG %.2f %s\n",
                     g_dBaskets, g_dTrades, g_dProfit, g_dComm, g_dSwap, g_dProfit + g_dComm + g_dSwap, cur);
   s += "Trang thai: " + g_status;
   Comment(s);
   DrawLevels(b);
  }

//+------------------------------------------------------------------+
//| Vong xu ly chinh                                                 |
//+------------------------------------------------------------------+
void ProcessCore()
  {
   MqlTick tk;
   if(!SymbolInfoTick(g_sym, tk) || tk.bid <= 0.0 || tk.ask <= 0.0 || tk.ask < tk.bid)
      return;
   UpdateNow(tk);
   g_lastProcessClk = GetTickCount64();
   CheckNewDay();

   string why = "";
   if(!TradingAllowed(why))
     {
      g_status = why;
      return;
     }

   SBasket b;
   ScanBasket(b);
   int n = b.nBuy + b.nSell;

//--- phat hien lenh moi (khop lenh cho / lenh nhoi / cap mo dau)
   bool newEntry = false;
   if(n > 0 && b.lastMsc > g_lastEntryMsc)
     {
      newEntry       = true;
      g_lastEntryMsc = b.lastMsc;
      PrintFormat("[THG] Lenh moi nhat: %s %.2f @ %s | Buy %d / Sell %d | ro %.2f",
                  (b.lastIsBuy ? "BUY" : "SELL"), b.lastLots, Px(b.lastOpen), b.nBuy, b.nSell, b.profit);
     }

//--- dang dong ca ro
   if(g_closing)
     {
      ProcessClosing(b);
      g_status = "Dang dong ca ro: " + g_closeReason;
      return;
     }

//--- ro bi dong tu ben ngoai (dong tay, stop out...)
   if(n == 0 && g_hadBasket)
     {
      g_hadBasket   = false;
      g_lastCloseMs = g_nowMs;
      PrintFormat("[THG] Ca ro da dong ngoai EA -> xoa lenh cho, nghi %d giay.", InpCooldownSec);
     }
   if(n > 0)
      g_hadBasket = true;

//--- bao ve trong ngay
   if(CheckDailyGuard() && n > 0)
     {
      BeginCloseAll("cham muc lo trong ngay", b);
      return;
     }

   if(n > 0)
     {
      ManageBasket(tk, b, newEntry);
      if(!g_closing)
         g_status = "Dang chay ro #" + (string)g_cycleNo;
      return;
     }

//--- khong co lenh: don lenh cho con sot, het thoi gian nghi thi mo chu ky moi
   if(CountOwnPendings() > 0)
      DeleteAllPendings();
   TryStartCycle(tk);
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
   g_sym       = _Symbol;
   g_isTester  = (MQLInfoInteger(MQL_TESTER) != 0);
   g_showPanel = InpShowPanel && (!g_isTester || MQLInfoInteger(MQL_VISUAL_MODE) != 0);

   if(!SymbolSelect(g_sym, true))
     {
      Print("[THG] Khong chon duoc symbol ", g_sym);
      return INIT_FAILED;
     }
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tick   = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_point <= 0.0)
      g_point = MathPow(10.0, -g_digits);
   if(g_tick <= 0.0)
      g_tick = g_point;

//--- kiem tra tham so
   if(InpDistanceScale <= 0.0 || InpPendingDistance <= 0.0 || InpAddOnStep <= 0.0 || InpTakeProfit <= 0.0)
     {
      Print("[THG] He so quy doi, khoang cach lenh cho, buoc nhoi va TP phai > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPendingTrailStep < 0.0 || InpEntryCloseDist < 0.0 || InpMaxSlippage < 0.0 || InpMaxSpreadStart < 0.0 ||
      InpCooldownSec < 0 || InpMaxPositionsSide < 0 || InpMaxLot < 0.0 || InpCommissionPerLot < 0.0 ||
      InpMaxBasketLoss < 0.0 || InpMaxBasketLossPct < 0.0 || InpPauseAfterStopMin < 0 ||
      InpDailyLossPct < 0.0 || InpDailyTargetPct < 0.0)
     {
      Print("[THG] Tham so khong duoc am");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBaseLot <= 0.0 || InpLotMultiplier < 1.0 ||
      (InpLotSizing == LOTS_BY_BALANCE && InpBalancePerBaseLot <= 0.0))
     {
      Print("[THG] Lot co so phai > 0, he so nhoi phai >= 1, so du moi lot co so phai > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 0 || InpEndHour > 23 ||
      InpStartMinute < 0 || InpStartMinute > 59 || InpEndMinute < 0 || InpEndMinute > 59)
     {
      Print("[THG] Gio/phut khong hop le");
      return INIT_PARAMETERS_INCORRECT;
     }

//--- chien luoc giu Buy va Sell cung luc -> bat buoc tai khoan Hedging
   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      string msg = "[THG] Tai khoan dang o che do NETTING/EXCHANGE. Chien luoc can giu Buy va Sell cung luc "
                   "-> hay mo tai khoan HEDGING (hau het san forex MT5 deu co).";
      Print(msg);
      Alert(msg);
      return INIT_FAILED;
     }

//--- quy doi khoang cach
   g_dist       = InpPendingDistance  * InpDistanceScale;
   g_trailStep  = InpPendingTrailStep * InpDistanceScale;
   g_addStep    = InpAddOnStep        * InpDistanceScale;
   g_tp         = InpTakeProfit       * InpDistanceScale;
   g_entryClose = InpEntryCloseDist   * InpDistanceScale;
   g_maxSpread  = InpMaxSpreadStart   * InpDistanceScale;
   g_slip       = InpMaxSlippage      * InpDistanceScale;

//--- san co cho dat lenh Stop tren ma nay khong
   long orderMode = SymbolInfoInteger(g_sym, SYMBOL_ORDER_MODE);
   g_stopOrdersOk = (orderMode == 0 || (orderMode & SYMBOL_ORDER_STOP) != 0);
   if(InpUsePendings && !g_stopOrdersOk)
      Print("[THG] Canh bao: san khong cho dat lenh Stop tren ", g_sym, " -> chay khong co cap Buy/Sell Stop");

//--- canh bao neu dung thong so vang cho ma khac
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(bid > 0.0 && g_dist > bid * 0.01)
      PrintFormat("[THG] Canh bao: khoang cach lenh cho %s qua lon so voi gia %s. Thong so mac dinh danh cho XAUUSD -> "
                  "hay dat InpDistanceScale (EURUSD 0.0001, USDJPY 0.01...).", Px(g_dist), Px(bid));

   double vmin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   if(InpLotSizing == LOTS_FIXED && InpBaseLot < vmin)
      PrintFormat("[THG] Canh bao: lot co so %.2f nho hon lot toi thieu cua san (%.2f) -> dung %.2f", InpBaseLot, vmin, vmin);

   SetupExpiration();
   CheckNewDay();
   InitLastClose();

//--- tiep tuc quan ly ca ro dang co (khoi dong lai terminal / doi tham so)
   SBasket b;
   ScanBasket(b);
   g_lastEntryMsc = b.lastMsc;
   g_hadBasket    = (b.nBuy + b.nSell > 0);
   if(g_hadBasket)
      PrintFormat("[THG] Tiep tuc quan ly ro dang mo: Buy %d / Sell %d, lai/lo %.2f", b.nBuy, b.nSell, b.profit);

   string lotSeq = "";
   for(int i = 0; i <= 8; i++)
      lotSeq += StringFormat("%s%.2f", (i == 0 ? "" : " "), AddOnLots(i));
   PrintFormat("[THG] %s | digits=%d tick=%s | lenh cho %s (keo khi > %s) | nhoi %s | TP %s | chot sau lenh moi >= %.2f %s | nghi %ds",
               g_sym, g_digits, DoubleToString(g_tick, g_digits), Px(g_dist), Px(g_dist + g_trailStep),
               Px(g_addStep), Px(g_tp), EntryCloseMoney(), AccountInfoString(ACCOUNT_CURRENCY), InpCooldownSec);
   PrintFormat("[THG] Lot theo so lenh cung chieu (0..8): %s | StopsLevel=%d FreezeLevel=%d",
               lotSeq, (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_FREEZE_LEVEL));

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
   ObjectsDeleteAll(0, OBJ_PREF);
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
//| Timer: xu ly du phong khi it tick + thong ke                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ulong now = GetTickCount64();
   if(!g_isTester && (now < g_lastProcessClk || now - g_lastProcessClk >= 1000))
      Process();
   if(g_showPanel)
     {
      if(g_lastStatsClk == 0 || now < g_lastStatsClk || now - g_lastStatsClk >= 2000)
        {
         UpdateDailyStats();
         g_lastStatsClk = now;
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
//--- lenh dong bat dong bo bi tu choi vi kieu khop lenh -> lan sau dung kieu khac
   if(trans.type == TRADE_TRANSACTION_REQUEST && request.symbol == g_sym && request.magic == InpMagic &&
      request.action == TRADE_ACTION_DEAL && result.retcode == TRADE_RETCODE_INVALID_FILL)
     {
      g_fillMarketOk = false;
      return;
     }
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == g_sym)
      Process();
  }
//+------------------------------------------------------------------+
