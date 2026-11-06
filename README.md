# Momentum Stop Scalper – EA MT5 (MQL5)

EA được dựng lại từ video quay màn hình MT5 trên điện thoại (TikTok @yaser100x, khoảng 47 giây, ngày 12/10/2026, 04:00–04:02 giờ máy chủ).
Mã nguồn: [`MQL5/Experts/MomentumStopScalper.mq5`](MQL5/Experts/MomentumStopScalper.mq5)

> Các tham số mặc định chính là thông số đọc được từ video: XAUUSD, 0.01 lot, lệnh chờ cách giá 0.05$, SL 0.30$, trailing 0.30$, tối đa 7 lệnh.

---

## 1. Phân tích video: quan sát được gì, suy ra quy tắc nào

Video được tách thành 129 khung hình (3 khung/giây, bỏ đoạn kết TikTok) để đọc từng con số trên màn hình Trade/History.

| # | Quan sát trong video (số liệu thật) | Quy tắc suy ra |
|---|---|---|
| 1 | Mã **XAUUSD.ecn**, khung **M1**, mọi lệnh đều **0.01 lot** | Lot cố định 0.01 |
| 2 | Lệnh Buy hiện giá Bid, lệnh Sell hiện giá Ask, chênh nhau **0.09** (ví dụ 4212.85 / 4212.94) | Spread ≈ 0.09 (tài khoản ECN) |
| 3 | Luôn có **1 Buy Stop và 1 Sell Stop cách nhau đúng 0.19**: 4215.18/4214.99, 4212.17/4211.98, 4212.98/4212.79, 4211.39/4211.20… Ví dụ Bid 4215.04, Ask 4215.13 thì Buy Stop = **Ask + 0.05**, Sell Stop = **Bid − 0.05** | Đặt cặp lệnh chờ ±0.05 quanh giá (0.09 spread + 2×0.05 = 0.19) |
| 4 | Giá chạy lên thì liên tục khớp thêm Buy: 4212.56 → 4213.18 → 4213.27 → 4213.59 → 4213.71 | Lệnh chờ khớp xong là đặt ngay lệnh mới cùng chiều, nên giá càng chạy càng nhồi thêm lệnh |
| 5 | Mọi lệnh thua đều lỗ **đúng −0.30**: Buy 4211.90→4211.60, Buy 4215.22→4214.92, Sell 4212.47→4212.77… | **Stop Loss = 0.30$** (30 pip vàng) |
| 6 | 7 lệnh Buy (4210.24…4212.19) đóng **cùng lúc, cùng giá**. Đỉnh Bid là 4212.74; số dư tăng 164.80 → 171.98 tương ứng giá đóng **4212.44 = 4212.74 − 0.30** | **Trailing Stop = 0.30$**, SL chung của các lệnh cùng chiều |
| 7 | 7 lệnh Buy khác đóng ở **4214.98** (lịch sử 04:01:46) sau khi giá lên 4215.28, tức là **4215.28 − 0.30** | Xác nhận trailing 0.30 |
| 8 | Lịch sử không có lệnh nào lỗ nhỏ kiểu −0.10 hay −0.20. Các lệnh thắng nhỏ nhất chỉ +0.07, +0.08, +0.11, +0.16 | Trailing **chỉ bắt đầu khi lãi > 0.30** (kiểu trailing cổ điển); trước đó SL giữ nguyên −0.30 |
| 9 | Khi đủ **7 lệnh** thì mục *Orders* trống, không còn lệnh chờ (t≈19s, 21.7–22.3s, 27–29s) | **Tối đa 7 lệnh mở**; đủ 7 thì không đặt lệnh chờ mới |
| 10 | Giá đi ngược thì Buy Stop bị kéo xuống theo (ví dụ khớp Buy 4211.56 xong, Buy Stop mới nằm ở 4211.47). Sell Stop 4210.83 được dời lên 4211.20 khi giá tăng 0.42 | Lệnh chờ bị bỏ xa thì được kéo theo giá (EA dùng ngưỡng 25 pip) |
| 11 | Mỗi lệnh mới khớp làm số dư giảm **0.07** (159.76 → 159.62 khi khớp 2 Buy) | Commission **0.07$/0.01 lot**, khoảng $7/lot, trừ ngay lúc vào lệnh |
| 12 | Tab History: **Deposit 154.00, Profit 319.43, Commission −292.74, Balance 180.69** | Khoảng **4.180 lệnh** (292.74 / 0.07). Lãi gộp ≈ 0.076$/lệnh, phí 0.07$/lệnh, **phí ăn gần hết lợi nhuận** |
| 13 | Từ 04:01:06 đến 04:01:49, commission tăng 6.51, tức **khoảng 93 lệnh trong 43 giây** | Giao dịch tần suất rất cao, khoảng 2 lệnh/giây |
| 14 | Biểu đồ M1 có một đường trung bình động màu trắng, nhưng EA vẫn mở cả Buy lẫn Sell bất kể giá nằm trên hay dưới đường đó | Đường MA **không** dùng làm bộ lọc |
| 15 | Trong 2 phút quay, vàng đang **bứt phá mạnh** (từ khoảng 4186 lên khoảng 4215) và số dư tăng 160.55 → 201.81 | Video chỉ quay đúng giai đoạn thuận lợi nhất cho chiến lược |

### Những điểm video không cho biết chắc chắn (EA để thành tham số)
- **Ngưỡng kéo lệnh chờ.** Từ khung hình chỉ thấy ngưỡng này nằm khoảng 0.22–0.42, nên mặc định là `PendingStep = 25 pip`.
- **Tối đa 7 lệnh.** Con số này suy từ quan sát. Video có lúc thấy 7 lệnh + 1 lệnh chờ, nên EA gốc dường như chỉ ngừng đặt lệnh mới chứ không xoá lệnh đang chờ. EA này làm giống vậy và có thêm tuỳ chọn `DeletePendingAtMax`.
- **Bộ lọc giờ, tin tức, spread** của bot gốc không thấy được. Trong EA chúng đều là tuỳ chọn.

---

## 2. Logic của EA

```
Mỗi tick (và ngay khi có lệnh khớp):
 ├─ 1. Quản lý lệnh đang mở
 │     ├─ SL = giá khớp ± 30 pip (chỉnh lại theo giá khớp thật nếu bị trượt giá)
 │     └─ Lãi > 30 pip  →  SL bám theo giá, cách 30 pip (bước 1 pip)
 ├─ 2. Kiểm tra bảo vệ ngày (nếu bật): lỗ/lãi ngày chạm ngưỡng → đóng hết, nghỉ đến ngày mới
 ├─ 3. Bộ lọc: spread ≤ MaxSpread, khung giờ (nếu bật)
 │     └─ không đạt → xoá lệnh chờ, chờ tiếp
 └─ 4. Nếu số lệnh mở < 7:
       ├─ Chưa có Buy Stop  → đặt Buy Stop  tại Ask + 5 pip (SL −30)
       ├─ Chưa có Sell Stop → đặt Sell Stop tại Bid − 5 pip (SL +30)
       └─ Lệnh chờ bị giá bỏ xa thêm ≥ 25 pip → kéo về sát giá
```

Lệnh Buy Stop vừa khớp sẽ được đặt lại ngay. Nếu giá tiếp tục đi lên thì lệnh mới lại khớp, nên EA **nhồi lệnh theo đà** (tối đa 7). Khi giá quay đầu, trailing 30 pip đóng cả cụm cùng một giá, còn Sell Stop đón chiều ngược lại.

---

## 3. Tham số (mặc định = video)

Đơn vị **pip** trong EA được quy đổi như sau: nếu symbol có 3 hoặc 5 chữ số thập phân thì 1 pip = 10 point, còn lại 1 pip = 1 point.
Với **vàng XAUUSD**, dù sàn báo giá 2 hay 3 số lẻ, **1 pip = 0.01$**, nên các con số trong video được giữ đúng.

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `InpEntryDistancePips` | 5 | Khoảng cách lệnh chờ so với Ask/Bid (0.05$) |
| `InpPendingStepPips` | 25 | Kéo lệnh chờ theo giá khi bị bỏ xa thêm 25 pip (0 = tắt) |
| `InpMaxPositions` | 7 | Tổng số lệnh mở tối đa (Buy + Sell) |
| `InpDeletePendingAtMax` | false | Có xoá lệnh chờ khi đã đủ số lệnh tối đa hay không |
| `InpLotMode` / `InpLots` | Cố định / 0.01 | Hoặc tự động: `InpLots` cho mỗi `InpBalancePerStep` số dư |
| `InpStopLossPips` | 30 | SL 0.30$ |
| `InpTakeProfitPips` | 0 | Không đặt TP (video không dùng TP) |
| `InpTrailingStopPips` | 30 | Trailing 0.30$ |
| `InpTrailingStartPips` | 30 | Trailing chạy khi lãi > 0.30$ |
| `InpTrailingStepPips` | 1 | Bước dời SL tối thiểu |
| `InpAlignSLToFill` | true | Đặt lại SL theo giá khớp thật (bù trượt giá) |
| `InpMaxSpreadPips` | 15 | Spread > 0.15$ thì tạm dừng đặt lệnh (video: 0.09) |
| `InpUseTimeFilter` | false | Lọc giờ theo giờ máy chủ |
| `InpMaxDailyLossPct` / `InpDailyTargetPct` | 0 / 0 | Bảo vệ ngày (0 = tắt) |
| `InpMagic` | 20261012 | Magic number, dùng để tách lệnh khi chạy nhiều chart |

---

## 4. Cài đặt và biên dịch ra file `.ex5`

1. MT5 → **File → Open Data Folder** → chép `MomentumStopScalper.mq5` vào `MQL5/Experts/`.
2. Mở **MetaEditor** (F4), mở file, nhấn **F7 (Compile)**. File `MomentumStopScalper.ex5` sẽ được tạo cùng thư mục.
3. Trong MT5: Navigator → Expert Advisors → kéo EA vào chart **XAUUSD** (hậu tố nào cũng được: `.ecn`, `m`, `.pro`…). Khung thời gian không quan trọng vì EA chạy theo tick.
4. Bật **Algo Trading** và tick **Allow Algo Trading** trong tab Common.
5. Nên chạy trên **VPS gần máy chủ sàn** (ping thấp). Chiến lược này sống nhờ tốc độ khớp lệnh.

---

## 5. "Chạy mọi sàn": EA tự thích ứng những gì

- **Không khoá** tài khoản, sàn, hay ngày hết hạn.
- Báo giá **2/3/4/5 số lẻ** và **hậu tố symbol** bất kỳ (EA dùng symbol của chart).
- **Kiểu khớp lệnh** FOK/IOC/RETURN: EA tự thử và ghi nhớ kiểu sàn chấp nhận.
- **Kiểu hết hạn lệnh chờ** GTC/DAY/SPECIFIED theo quy định từng sàn.
- **Stops Level / Freeze Level**: tự nới khoảng cách. Nếu sàn liên tục từ chối vì giá quá gần, EA tự cộng thêm khoảng cách và ghi log.
- **Lot min/max/step** của từng sàn; kiểm tra ký quỹ trước khi đặt lệnh.
- Lỗi phía sàn (đóng cửa thị trường, quá nhiều request, mất kết nối…) được xử lý bằng cách **tạm nghỉ hợp lý**, không gửi lệnh dồn dập lên máy chủ.
- Mã chỉ cho phép đánh một chiều (Long only / Short only) thì EA chỉ đặt chiều được phép.
- Bảng thông tin trên chart hiển thị spread, số lệnh, lãi/lỗ thả nổi, và **lãi gộp / phí / lãi ròng trong ngày**.

**Giới hạn bắt buộc:** cần **tài khoản HEDGING**, vì chiến lược giữ Buy và Sell cùng lúc. Trên tài khoản Netting, EA báo lỗi và không chạy. Hầu hết sàn forex MT5 đều cho mở tài khoản Hedging.

### Dùng cho cặp khác (EURUSD, GBPUSD…)
Bộ mặc định được hiệu chỉnh cho **vàng**. Nếu muốn giữ đúng **tỉ lệ so với spread và phí** như trong video, điểm khởi đầu để *kiểm thử* cho các cặp forex chính trên tài khoản ECN là:
`Entry 0.5 · SL 3 · Trailing 3 · TrailingStart 3 · PendingStep 2.5 · MaxSpread 1.0` (đơn vị pip forex).
Bộ số này chỉ để bắt đầu thử nghiệm, chưa được kiểm chứng. Bắt buộc tối ưu bằng Strategy Tester với dữ liệu tick thật của chính sàn bạn dùng.

---

## 6. Kiểm thử trước khi chạy tiền thật

- Strategy Tester → Modelling: **"Every tick based on real ticks"**. Các chế độ khác cho kết quả sai hoàn toàn với scalper kiểu này.
- Đặt đúng **commission** của sàn. Chính video cho thấy phí chiếm khoảng 92% lãi gộp.
- Chạy **demo ít nhất 1–2 tuần** trên đúng sàn và đúng loại tài khoản định dùng.

---

## 7. ⚠️ Cảnh báo rủi ro (rút ra từ chính số liệu trong video)

1. **Lợi thế mỗi lệnh cực mỏng.** Lãi gộp khoảng 0.076$ mỗi lệnh, phí 0.07$ mỗi lệnh, tức lãi ròng chỉ khoảng **0.006$/lệnh** sau khoảng 4.180 lệnh. Spread cao hơn 0.01–0.02$ hoặc phí cao hơn một chút là **lỗ ròng**.
2. Kết quả phụ thuộc rất lớn vào **loại tài khoản**. Video dùng tài khoản ECN spread khoảng 0.09$. Tài khoản Standard có spread vàng 0.20–0.35$ gần như chắc chắn thua.
3. Video chỉ quay **2 phút đẹp nhất**, lúc giá đang bứt phá mạnh. Khi thị trường đi ngang và giật qua lại, cặp Buy Stop/Sell Stop bị khớp cả hai rồi dính SL liên tục.
4. Tần suất khoảng 2 lệnh/giây và sửa SL liên tục. Một số sàn **cấm hoặc hạn chế "hyperactive trading"/scalping siêu ngắn**, có thể khoá tài khoản hoặc huỷ lợi nhuận. Hãy đọc điều khoản sàn.
5. Trượt giá, độ trễ và tick giả khác nhau giữa các sàn. **Cùng một EA có thể lãi ở sàn A và lỗ ở sàn B.**
6. EA **không đảm bảo lợi nhuận**. Chỉ dùng số vốn bạn chấp nhận mất.
