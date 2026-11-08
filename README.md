# EA MT5 (MQL5) dựng lại từ video giao dịch

| EA | Video gốc | Mã nguồn | Tài liệu |
|---|---|---|---|
| **Trailing Hedge Grid** (mới) | TikTok @trailingstop, 75 giây, XAUUSD M1, 06/11/2026 | [`MQL5/Experts/TrailingHedgeGrid.mq5`](MQL5/Experts/TrailingHedgeGrid.mq5) | Trang này |
| Momentum Stop Scalper | TikTok @yaser100x, 47 giây, XAUUSD M1, 12/10/2026 | [`MQL5/Experts/MomentumStopScalper.mq5`](MQL5/Experts/MomentumStopScalper.mq5) | [`docs/MomentumStopScalper.md`](docs/MomentumStopScalper.md) |

---

# Trailing Hedge Grid

Mỗi chu kỳ EA mở **một cặp BUY + SELL** và đặt **Buy Stop / Sell Stop cách giá 3.00 có trailing**. Khi giá chạy theo một hướng, EA **nhồi lệnh cùng chiều** với khối lượng ×1.2. Khi lệnh vào gần nhất lãi **1.10**, EA **đóng cả rổ** cùng lúc, nghỉ **30 giây** rồi lặp lại.
Tham số mặc định chính là các con số đọc được từ video.

## 1. Phân tích video

### Video cho thấy gì
- Quay màn hình app MT5 trên iPhone (giao diện tiếng Việt). Video dài 74.9 giây nhưng đồng hồ máy đi từ 08:02 đến 08:08, tức **khoảng 6 phút thực được tua nhanh ~5 lần**. Giờ máy chủ tương ứng là 03:02:48 → ~03:08:30 ngày 06/11/2026.
- Tài khoản demo, đòn bẩy 1:500, không có phí giao dịch và swap. Mã XAUUSD, khung M1, **spread 0.12**.
- Số dư đi từ **102 123.00 → 102 173.59** sau 4 rổ lệnh. Tab Lịch sử "Hôm nay" ghi lợi nhuận 450.24 → 461.29.
- Cách làm: tách 450 khung hình (6 khung/giây) và 30 khung/giây quanh mỗi lần vào/đóng lệnh. Đọc tab Giao dịch (giá vào, giá hiện tại, lãi/lỗ từng lệnh), các đường lệnh trên biểu đồ, và **khoảng 150 lệnh đã đóng trong tab Lịch sử** để kiểm chứng.

### 4 rổ lệnh trong video

| Rổ | Giờ máy chủ | Các lệnh (giá vào) | Đóng tại | Lãi |
|---|---|---|---|---|
| #1 | 03:02 → 03:04:03 | BUY 0.05 @4090.56, 0.06 @4092.63, 0.05 @4093.38, 0.09 @4095.63 · SELL 0.05 @4090.56, 0.05 @4092.19, 0.05 @4094.26, 0.09 @4091.94, 0.05 @4095.49, 0.12 @4093.29, 0.05 @4091.62 (Sell Stop) | Bid 4090.36 / Ask 4090.48 | **+28.31** |
| #2 | 03:04:32 → ~03:04:55 | BUY 0.05 @4090.58 · SELL 0.05 @≈4090.46 · BUY 0.05 @4089.33 | Bid 4090.43 | **+4.30** |
| #3 | ~03:05:20 → 03:05:33 | BUY 0.05 @4091.06 · SELL 0.05 @4091.25 · BUY 0.06 @4093.32 · BUY 0.05 @4094.24 (Buy Stop) | Bid 4094.32 | **+6.75** |
| #4 | 03:06:03 → ~03:08:05 | BUY 0.05 @4094.49 · SELL 0.05 @4094.13 · SELL 0.05 @4091.99 (Sell Stop) · SELL 0.06 @4091.74 | Ask ≈4090.61 | **+11.23** |

Lãi của từng rổ đã được tính lại từ giá vào/giá đóng và khớp đúng với mức tăng số dư trên màn hình.

### Quy tắc suy ra và bằng chứng

| # | Quy tắc | Bằng chứng trong video |
|---|---|---|
| 1 | **Mở chu kỳ**: BUY 0.05 + SELL 0.05 lệnh thị trường, kèm **Buy Stop tại Ask + 3.00, Sell Stop tại Bid − 3.00** (0.05) | #2: 4093.63 / 4087.51 (Bid 4090.51, Ask 4090.63). #3: 4094.24 / 4088.11. #4: 4098.11 / 4091.99. Lịch sử: rổ nào cũng có cặp BUY/SELL 0.05 giá gần nhau (4092.28/4092.15, 4089.43/4089.31…) |
| 2 | **Lệnh chờ trailing**: chỉ kéo khi cách giá **> 3.00 + 2.00**, kéo về cách giá 3.00 | Có kéo khi cách 5.16 (#4: Buy Stop 4098.11 → 4095.95), 5.19 (#3: Sell Stop 4088.11 → 4090.30), 5.10 (#1: 4096.68 → 4094.58). **Không** kéo khi cách 4.68 (#2), 4.87 (#1), 3.84 (#4) |
| 3 | Lệnh chờ khớp → **đặt lệnh chờ mới cùng chiều** cách giá 3.00 | #1: Sell Stop 4091.62 khớp → Sell Stop mới 4088.33. #4: 4091.99 khớp → 4088.91 |
| 4 | **Nhồi lệnh theo xu hướng**: giá đi thêm **2.20** so với lệnh cùng chiều mới nhất (BUY nhồi khi giá lên, SELL nhồi khi giá xuống) | SELL 0.12 @4093.29 = 4095.49 − **2.20** đúng từng cent (trước đó giá chạm 4093.38–4093.39 hai lần mà chưa nhồi, nên bước không phải 2.0). BUY 0.09 @4095.63 (4093.38 + 2.25), #3 BUY 0.06 @4093.32 (4091.06 + 2.26), SELL 0.09 @4091.94 (4094.26 − 2.32), #4 SELL 0.06 @4091.74 (4094.13 − 2.39) |
| 5 | **Lot nhồi = 0.05 × 1.2ⁿ** (n = số lệnh cùng chiều đang mở, làm tròn) | 0.06 khi có 1 lệnh cùng chiều, 0.09 khi có 3, 0.12 khi có 5. Lịch sử có đúng dãy 0.10, 0.15, 0.18, 0.21, 0.31, 0.45, 0.64, 0.77 (= 0.05 × 1.2⁴ … 1.2¹⁵) |
| 6 | **Chốt cả rổ** khi lệnh vào gần nhất lãi **1.10** và cả rổ đang lãi | #2 đóng tại Bid 4090.43 = 4089.33 + 1.10 đúng từng cent (trước đó giá lên 4090.37 nhưng chưa đóng). #1 đóng ở tick Ask 4090.48 ≤ 4091.62 − 1.10, tick trước đó Ask 4090.53 chưa đủ. #4 đóng khi Ask 4090.63 ≤ 4091.74 − 1.10 |
| 7 | Vừa có lệnh mới mà rổ đã lãi đủ thì **chốt ngay** | #3: Buy Stop khớp khi rổ lãi khoảng +4.3 → EA xoá Sell Stop và đóng hết trong khoảng 1 giây (+6.75). Lịch sử: các rổ 02:46:17, 02:38:32, 01:30:44 đều đóng ngay sau một lệnh mới |
| 8 | Đóng rổ: **xoá lệnh chờ trước**, rồi đóng tất cả lệnh **cùng một giá** | #3: mục "Các lệnh" trống trong khi lệnh vẫn mở. #1: cả 11 lệnh đóng cùng giá lúc 03:04:03 |
| 9 | **Nghỉ 30 giây** giữa hai chu kỳ | 03:04:03 → 03:04:32, 03:05:33 → 03:06:03. Lịch sử: 01:20:56 → 01:21:26, 02:13:31 → 02:14:01, 02:38:32 → 02:39:03, 03:01:02 → 03:01:33 |
| 10 | Không có SL/TP gắn vào lệnh, không dùng chỉ báo | Biểu đồ không có đường SL/TP, chỉ có nến M1 |

### Những phần video không cho biết chắc chắn (đọc kỹ)
- **4 lệnh 0.05 vào ngược xu hướng bằng lệnh thị trường**: SELL @4095.49 ngay sau đỉnh 4095.79, BUY @4089.33 sau đáy 4088.83, SELL @4092.19 và @4094.26 (trước khi video bắt đầu). Chúng giống lệnh vào khi giá hồi 0.30. Nhưng ở rổ #3 và #4, giá hồi tương tự mà bot không vào lệnh, nên **không tìm được quy tắc nhất quán** (có thể là lệnh vào tay). EA **không** mô phỏng các lệnh này. Vì vậy đường đi của rổ #1 và #2 trong EA sẽ khác video. Rổ #3 và #4 thì đúng logic.
- Lịch sử có 4 lần **cặp lệnh đầu tiên sau một rổ lớn bị đóng sau khoảng 1 giây với lỗ −1.4 đến −2.2** (01:21:26, 02:14:01, 02:39:03, 03:01:33). Không tìm được quy tắc, nên EA không mô phỏng.
- Ngưỡng của quy tắc 7 chỉ ước lượng được trong khoảng 2.5–4.5 USD (với lot 0.05). EA dùng 0.80 × giá trị lot cơ sở, tức 4.00 USD.
- Trước 02:00 bot dùng cài đặt khác: lot 0.01 lúc 01:09, các lot 0.08, 0.11, 0.14, 0.17, 0.23, 0.25, 0.30, 0.44 không theo ×1.2. EA dùng cài đặt của giai đoạn gần nhất, chính là giai đoạn quay video.

---

## 2. Logic của EA

```
Mỗi tick (và ngay khi có lệnh khớp):
 ├─ Đang đóng rổ? → xoá lệnh chờ, đóng mọi lệnh (bất đồng bộ, gửi lại sau 1.5s nếu còn)
 ├─ Có rổ đang mở:
 │   ├─ [bảo vệ, mặc định tắt] lỗ thả nổi ≥ giới hạn → đóng hết, nghỉ N phút
 │   ├─ vừa có lệnh mới và rổ lãi ≥ 0.80 × giá trị lot cơ sở → đóng hết
 │   ├─ lệnh vào gần nhất lãi ≥ 1.10 và rổ lãi > 0 → đóng hết
 │   ├─ nhồi BUY : Ask ≥ BUY mới nhất + 2.20 → BUY lot 0.05 × 1.2^(số BUY)
 │   ├─ nhồi SELL: Bid ≤ SELL mới nhất − 2.20 → SELL lot 0.05 × 1.2^(số SELL)
 │   └─ lệnh chờ: thiếu thì đặt (Ask + 3.00 / Bid − 3.00); cách giá > 5.00 thì kéo về 3.00
 └─ Không có lệnh:
     └─ đã nghỉ đủ 30s và qua bộ lọc → mở BUY 0.05 + SELL 0.05, đặt Buy Stop / Sell Stop
```

Lot nhồi theo số lệnh cùng chiều đang mở:

| n | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| lot | 0.05 | 0.06 | 0.07 | 0.09 | 0.10 | 0.12 | 0.15 | 0.18 | 0.21 | 0.26 | 0.31 | 0.37 | 0.45 | 0.53 | 0.64 | 0.77 |

---

## 3. Tham số (mặc định = video)

Khoảng cách tính bằng **đơn vị giá**: với XAUUSD, 1.00 = 1 USD/oz. Tham số đúng trên mọi sàn, dù sàn báo giá vàng 2 hay 3 số lẻ.

| Nhóm | Tham số | Mặc định | Ý nghĩa |
|---|---|---|---|
| Khối lượng | `InpLotSizing` | Cố định | Hoặc tự động: `InpBaseLot` cho mỗi `InpBalancePerBaseLot` số dư |
| | `InpBaseLot` | 0.05 | Lot cặp mở đầu và lệnh chờ |
| | `InpLotMultiplier` | 1.20 | Lot nhồi = cơ sở × hệ số^n |
| | `InpLotRounding` | Gần nhất | Như video (0.0864 → 0.09). Chọn "xuống" để ít rủi ro hơn |
| | `InpMaxLot` | 0 | Trần lot một lệnh (0 = không giới hạn) |
| Khoảng cách | `InpDistanceScale` | 1.0 | Hệ số quy đổi cho mã khác (mục 6) |
| | `InpPendingDistance` | 3.00 | Buy Stop = Ask + d, Sell Stop = Bid − d |
| | `InpPendingTrailStep` | 2.00 | Kéo lệnh chờ khi cách giá > d + bước |
| | `InpAddOnStep` | 2.20 | Bước nhồi so với lệnh cùng chiều mới nhất |
| | `InpTakeProfit` | 1.10 | Lệnh vào gần nhất lãi bằng khoảng này thì chốt rổ |
| | `InpEntryCloseDist` | 0.80 | Ngưỡng chốt ngay sau lệnh mới, = khoảng này × giá trị lot cơ sở (4.00 USD với 0.05 lot vàng; 0 = tắt) |
| | `InpMaxSlippage` | 0.50 | Trượt giá tối đa cho lệnh thị trường |
| Chu kỳ | `InpUsePendings` / `InpUseAddOns` | bật / bật | Tắt từng phần nếu muốn thử nghiệm |
| | `InpCooldownSec` | 30 | Nghỉ giữa hai chu kỳ (giây) |
| | `InpMinBasketProfit` | 0 | Rổ phải lãi hơn mức này mới chốt TP |
| | `InpMaxPositionsSide` | 0 | Số lệnh tối đa mỗi chiều (0 = không giới hạn, như video) |
| | `InpCommissionPerLot` | 0 | Phí 2 chiều mỗi lot. **Tài khoản có phí phải điền**, để EA tính lãi ròng khi chốt |
| Bộ lọc chu kỳ mới | `InpMaxSpreadStart` | 0 | Spread tối đa để mở chu kỳ (0 = tắt) |
| | `InpUseTimeFilter` … | tắt | Khung giờ mở chu kỳ mới (giờ máy chủ) |
| Bảo vệ (mặc định tắt) | `InpMaxBasketLoss` / `InpMaxBasketLossPct` | 0 | Rổ lỗ thả nổi đến mức này thì đóng hết |
| | `InpPauseAfterStopMin` | 60 | Nghỉ bao nhiêu phút sau khi cắt lỗ rổ |
| | `InpDailyLossPct` / `InpDailyTargetPct` | 0 | Lỗ ngày: đóng hết, nghỉ đến mai. Đạt mục tiêu ngày: không mở chu kỳ mới |
| Khác | `InpMagic` | 20261106 | Chạy nhiều chart cùng mã thì mỗi chart một magic |
| | `InpAsyncClose` | bật | Gửi lệnh đóng gần như cùng lúc để cả rổ đóng cùng giá, như video |
| | `InpShowPanel` / `InpDrawLevels` | bật | Bảng thông tin và đường mức TP, mức nhồi trên chart |

---

## 4. Cài đặt và biên dịch ra `.ex5`

1. MT5 → **File → Open Data Folder** → chép `TrailingHedgeGrid.mq5` vào `MQL5/Experts/`.
2. Mở **MetaEditor** (F4), mở file, nhấn **F7 (Compile)**. File `TrailingHedgeGrid.ex5` được tạo cùng thư mục.
3. Trong MT5: Navigator → Expert Advisors → kéo EA vào chart **XAUUSD** (hậu tố nào cũng được: `m`, `.ecn`, `.pro`…). Khung thời gian không ảnh hưởng vì EA chạy theo tick.
4. Bật **Algo Trading** và tick **Allow Algo Trading** trong tab Common.
5. Nên chạy trên **VPS gần máy chủ sàn**. Video cho thấy nhiều lệnh khớp lệch giá 0.1–0.4 khi giá chạy nhanh.

Khi chạy, tab **Experts** ghi log từng bước: mở chu kỳ, nhồi lệnh, lệnh chờ khớp, kéo lệnh chờ, chốt rổ kèm lãi/lỗ. Có thể dùng log này để so với video.

---

## 5. Chạy trên mọi sàn: EA tự thích ứng những gì

- **Không khoá** tài khoản, sàn hay ngày hết hạn. Dùng symbol của chart, nên hậu tố nào cũng được.
- Giá **2/3/4/5 số lẻ**, tick size, lot min/max/step của từng sàn.
- Kiểu khớp lệnh **FOK/IOC/RETURN**: EA tự thử và ghi nhớ kiểu sàn chấp nhận. Kiểu hết hạn lệnh chờ **GTC/DAY/SPECIFIED** theo quy định của sàn.
- **Stops level / freeze level**: tự nới khoảng cách lệnh chờ, không sửa lệnh khi đang bị đóng băng.
- Kiểm tra **ký quỹ** trước mỗi lệnh. Lỗi phía sàn (đóng cửa, quá nhiều request, mất kết nối, hết tiền…) được xử lý bằng cách tạm nghỉ hợp lý, không gửi lệnh dồn dập.
- Khởi động lại terminal hoặc đổi tham số: EA **tiếp tục quản lý rổ đang mở** và giữ đúng thời gian nghỉ (đọc từ lịch sử).
- Sàn không cho lệnh Stop trên mã đó: EA chạy tiếp, chỉ không có cặp Buy Stop/Sell Stop.

**Giới hạn bắt buộc:** cần **tài khoản HEDGING**, vì chiến lược giữ BUY và SELL cùng lúc. Trên tài khoản Netting, EA báo lỗi và không chạy. Hầu hết sàn forex MT5 đều cho mở tài khoản Hedging.

## 6. Dùng cho mã khác

Bộ mặc định đo trên **vàng**. Với mã khác, đặt `InpDistanceScale` để mọi khoảng cách co lại theo tỉ lệ (lot không đổi):

| Mã | `InpDistanceScale` | Lệnh chờ / bước nhồi / TP thành |
|---|---|---|
| XAUUSD | 1.0 | 3.00 / 2.20 / 1.10 USD |
| EURUSD, GBPUSD, AUDUSD… (5 số lẻ) | 0.0001 | 3.0 / 2.2 / 1.1 pip |
| USDJPY, EURJPY, GBPJPY (3 số lẻ) | 0.01 | 3.0 / 2.2 / 1.1 pip |

Bộ số này chỉ là điểm khởi đầu, chưa kiểm chứng. Nguyên tắc gần đúng: TP nên bằng khoảng 9 lần spread thường gặp (vàng: 1.10 so với spread 0.12). Bắt buộc tối ưu bằng Strategy Tester với dữ liệu tick thật.

## 7. Kiểm thử trước khi chạy tiền thật

- Strategy Tester → Modelling: **"Every tick based on real ticks"**. Chiến lược phụ thuộc từng tick nên các chế độ khác cho kết quả sai.
- Điền đúng **commission** của sàn vào `InpCommissionPerLot` và cấu hình phí trong Tester.
- Chạy **demo ít nhất 2–4 tuần**, phải gồm những ngày giá đi ngang giật hai chiều, vì đó là lúc rổ phình to.

## 8. ⚠️ Cảnh báo rủi ro (rút ra từ chính lịch sử trong video)

1. Đây là **lưới nhồi lệnh gấp thếp (martingale theo xu hướng)**, không có cắt lỗ mặc định. Lịch sử cùng ngày có rổ hơn 27 lệnh, tổng khoảng 5.3 lot (từ lot cơ sở 0.05), lot đơn lẻ lên tới 0.77 (gấp 15 lần), có lệnh đơn lẻ lỗ −240 USD.
2. Video chạy trên tài khoản demo **102 000 USD** với lot 0.05, tương đương **0.01 lot cho mỗi khoảng 20 000 USD**. Tài khoản nhỏ hơn mà vẫn dùng 0.05 lot thì rủi ro cháy tài khoản cao hơn nhiều lần. Dùng `LOTS_BY_BALANCE` để giữ tỉ lệ này.
3. Lợi nhuận mỗi rổ nhỏ (+4 đến +28 USD) so với lỗ thả nổi có thể gặp. Video chỉ quay 6 phút lúc thị trường thuận lợi.
4. Phí giao dịch và spread rộng làm thay đổi kết quả rất nhiều. Tài khoản Standard có spread vàng 0.25–0.40 sẽ khác hẳn tài khoản spread 0.12 trong video.
5. Nên bật ít nhất một lớp bảo vệ: `InpMaxBasketLossPct` (ví dụ 5–10%), `InpMaxPositionsSide` hoặc `InpMaxLot`, và `InpDailyLossPct`.
6. EA **không đảm bảo lợi nhuận**. Chỉ dùng số vốn bạn chấp nhận mất.
