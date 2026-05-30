# MATLAB OFDM Jamming & Anti-Jamming Project

## 專案簡介
本專案基於 MATLAB 與 USRP (軟體定義無線電)，實作了一個完整的 802.11a/g OFDM 收發系統，並針對 OFDM 實體層 (PHY Layer) 的各個脆弱點，開發了 12 種無線電干擾 (Jamming) 攻擊模型（從結構化的 preamble/pilot/CP 注入，到寬頻 / 限頻 / 單頻 / 多頻 CW / 假 frame 覆蓋）。接收端具備即時的鏈路品質監看、干擾偵測與 CRC 完整性驗證。本專案可用於評估無線通訊網路在惡意干擾下的穩健性，並測試未來的防禦 (Anti-jamming) 策略。

## 檔案結構

主要實驗碼已重構為參數驅動的 `OFDM_Jammer_Project/`；舊版 `jam_experiment/` 保留作為回歸對照，等硬體 parity 驗證後再退役。

```
OFDM_Jammer_Project/
├── tx_console.m                  ENTRY (B210): default = full sweep;
│                                              tx_console(mode, power) pins one attack
├── rx_console.m                  ENTRY (N210): default = full sweep;
│                                              rx_console(mode) locks RX strategy
├── tx_burst_console.m            ENTRY (B210, burst mode): duty-cycled TX +
│                                              one of 5 jammer firing patterns
├── rx_burst_console.m            ENTRY (N210, burst mode): per-bucket SNR/BER
│                                              + TX burst-index inference + .mat log
├── tx_burst_app.m                GUI front-end for tx_burst_console
│                                              (Start/Stop, sweep, preset, snapshot)
├── rx_burst_app.m                GUI front-end for rx_burst_console
│                                              (live BER/SNR charts + above)
├── selftest.m                    digital loopback parity check (no hardware)
│
├── config/
│   ├── load_parameters.m         single source of truth: spec / tx / rx
│   │                             / sched / detect / knob
│   └── default_burst_opts.m      burst orchestration defaults (duty cycle,
│                                 jammer pattern, RX bucket size, etc.)
│
├── core/                         TX/RX shared low-level
│   ├── gen_sts.m / gen_lts.m
│   ├── gen_ofdm_symbol.m / gen_ofdm_data.m
│   ├── build_frame.m / frame_info.m
│   ├── process_capture.m         RX: detect → CFO → H → demod → BER/SNR
│   ├── detect_sts_mf.m / detect_sts_autocorr.m
│   ├── estimate_channel.m / ofdm_demod_symbol.m / equalize_symbol.m
│   ├── init_usrp_tx.m / init_usrp_rx.m
│   ├── compute_crc16.m           real CRC-16-CCITT
│   ├── normalize_jammer.m / default_rxcfg.m / feed_jam_const.m
│   ├── make_dashboard.m / update_dashboard.m
│   └── snapshot_figs.m           dump all open figures to PNG (used by GUI apps)
│
├── modes/                        one file per attack: TX build + RX rxcfg
│   ├── mode00_baseline.m
│   ├── mode01_sts_sync.m         (TODO2 STS timing sync)
│   ├── mode02_coarse_cfo.m       (TODO3 STS coarse CFO, structured only)
│   ├── mode03_fine_cfo.m         (TODO4 LTS fine CFO)
│   ├── mode04_pilot_cfo.m        (TODO5 pilot CFO)
│   ├── mode05_chan_est.m         (TODO6 LTS channel estimation)
│   ├── mode06_cp.m               (TODO7 CP circular convolution)
│   ├── mode07_flower.m           (TODO8 high-power data overlay)
│   ├── mode08_broadband.m        (TODO9 broadband constant)
│   ├── mode09_bandlimited_awgn.m (TODO9-2 band-limited AWGN; BW sweep)
│   ├── mode10_single_cw.m        (TODO10 single CW)
│   ├── mode11_multi_cw.m         (TODO11 multi CW)
│   ├── mode12_fake_frame.m       (TODO12 fake frame overlay)
│   └── mode_registry.m           expands (mode × type × sweep) → schedule
│
└── scripts/
    ├── run_tx_loop.m             TX while-loop body (full-sweep mode)
    ├── run_rx_loop.m             RX while-loop body (full-sweep mode)
    ├── run_tx_burst.m            TX burst loop: duty cycle + jammer pattern,
    │                             exposes uiCtx hooks for GUI Stop/progress
    └── run_rx_burst.m            RX burst loop: bucket-flush stats + TX-burst
                                  inference, uiCtx hooks for live chart updates
```

* **OFDM_Jammer_Project/** — 重構後的主架構（建議從這裡跑實驗）
    * `tx_console.m`: B210 發射端入口。`tx_console()` 跑完整 22 階段 sweep；`tx_console(mode, power)` 鎖定單一攻擊與功率。
    * `rx_console.m`: N210 接收端入口；對應 TX 的 mode 切換 RX 解調策略。
    * `config/load_parameters.m`: 全部硬體 / OFDM spec / 排程 / 偵測門檻 / 功率 knob 的單一來源，杜絕「兩支腳本 spec 必須完全一致」的踩雷。
    * `core/`: 共用底層 — 訊號產生 (`gen_sts/lts/ofdm_*`)、frame 組裝 (`build_frame`, `frame_info`)、接收鏈 (`process_capture` + 兩種 STS 偵測器 + 通道估計 + 等化)、USRP 包裝、CRC-16-CCITT、儀表板。
    * `modes/mode00..mode12.m`: 每個攻擊獨立一檔，同時擁有自己的 TX `build` 與 RX `rxcfg`；加上 `mode_registry.m` 把 (mode × type × sweep) 展開成排程，徹底解決 TX/RX 三陣列手動同步的問題。
    * `scripts/run_tx_loop.m`, `run_rx_loop.m`: 主 while 迴圈，吃 params + schedule + USRP handle。
    * `selftest.m`: 數位 loopback parity check（無需硬體）— 對每個排程階段建 jammer + 跑 `process_capture`，輸出 detect / BER / SNR。
* **基礎收發框架**（Lab 原版）
    * `usrp_ofdm_tx.m`: 純淨 OFDM 封包發射器 (Baseline)。
    * `usrp_ofdm_monitor.m`: OFDM 接收器與監看儀表板。
* **jam_experiment/**（重構前的歷史版本，保留至 parity 驗收完成）
    * `jam_tx.m`, `jam_monitor.m`: 原本的 TX/RX 腳本；功能與 OFDM_Jammer_Project 等價，但所有 helpers / spec / 排程都是手抄複製。
* **演算法核心**
    * `jammer1.m`: 干擾與防禦機制的原型沙盒；攻擊邏輯與 CRC-16 已併入 `OFDM_Jammer_Project/core/`，本檔保留以利對照。

## 攻擊模式列表
參照論文 *Jamming Attacks and Anti-Jamming Strategies in Wireless Networks*，目前已實作的攻擊模式：

**結構化攻擊（針對 OFDM 同步／估計鏈路特定環節）：**
1.  **NO ATTACK:** 基線傳輸。
2.  **STS 時間同步攻擊 (TODO2):** 錯置封包起點。
3.  **STS 粗頻偏 (CFO) 攻擊 (TODO3):** 注入虛假 coarse CFO。
4.  **LTS 細頻偏 (CFO) 攻擊 (TODO4):** 只攻擊 LTS copy1，留 copy2 給 RX 估通道，孤立 fine CFO 影響。
5.  **Pilot CFO 攻擊 (TODO5):** 單獨干擾導護子載波。
6.  **LTS 通道估計攻擊 (TODO6):** 破壞等化器 $H$ 矩陣估計。
7.  **CP 循環卷積攻擊 (TODO7):** 寫入錯誤 CP 引發符號間干擾 (ISI)。
8.  **高功率資料覆蓋 / Flower 攻擊 (TODO8):** 於 data 子載波打出花瓣狀星座干擾。

**寬頻 / 限頻 / CW 攻擊（不依賴 OFDM 內部結構，泛用型干擾）：**
9.  **Broadband Constant Jamming (TODO9):** 整個 frame 全頻段複數高斯雜訊。
10. **限頻 AWGN (TODO9-2):** 只在 ±BW/2 範圍內注入雜訊，可 sweep 多種 `awgn_bw_ratio` 比較窄頻 vs. 寬頻效果。
11. **單頻 CW (TODO10):** 單一頻偏的連續波干擾。
12. **多頻 CW (TODO11):** 多個頻率／振幅的連續波組合。
13. **假 Frame 覆蓋 (TODO12):** 自訂 seed 重新產生 STS+LTS+OFDM data 整段假 frame 對打。

干擾強度由 `knob.noise_power`（純雜訊變體用）與 `knob.jam_power_scale`（結構化變體用）控制，最終以 victim RMS 倍數做 whole-frame 正規化，方便掃描功率對連結的影響。

## Burst-mode 排程實驗（新增，**未在 USRP 上驗證**）

`tx_burst_console` / `rx_burst_console` 與對應的 GUI app（`tx_burst_app` / `rx_burst_app`）是另一條獨立的執行路徑，跟原本的「22 階段 sweep」完全分開。原本的 `tx_console` / `rx_console` / `run_tx_loop` / `run_rx_loop` 不受影響。

### 解決什麼問題
原本的 console 是「連續傳輸 + 連續 jammer」。burst 模式讓你可以：

* **TX 週期傳**：每個 burst 送 `framesPerBurst` 個 frame，然後沉默 `txPeriodFrames - framesPerBurst` 個 frame 的時間，可以乾淨地把每個 burst 當成一次獨立的「打靶」。
* **Jammer 5 種觸發 pattern**：
    * `'continuous'` — 一直開（舊行為）
    * `'periodic'` — 自己的週期，或對齊 TX duty
    * `'random'` — 每個 frame 獨立 Bernoulli
    * `'random_bursts'` — 每個 TX burst 一次 Bernoulli（整 burst 開或關）
    * `'single_shot'` — 只在指定 burst index 開火（demo「精準一擊」）
* **RX 桶式累積**：每收到 `rxFramesPerReport` 個 frame 結算一次平均 SNR/BER + 持續累積總計；沒有 TX/RX 時鐘同步，burst 邊界從「相鄰 detection 的時間差 > 預期 off 一半」推回去。
* **`.mat` log + offline 畫圖**：RX 結束自動存 (`burst.logToMat=true`)，可離線畫 BER vs bucket。
* **idle auto-stop**：TX 可能只跑十幾秒，RX 預設等 480s 太久 → 設 `rxAutoStopIdleSec` 自動結束。

### GUI（`tx_burst_app` / `rx_burst_app`）
* 純 `uifigure` 程式碼版（.m，git 友善），不是 App Designer .mlapp。
* TX 端：mode dropdown、pattern dropdown、burst 參數 spinner、power slider、Dry run checkbox、Save/Load preset、📸 Snapshot、Start/Stop。
* RX 端：同樣的選單 + RX 桶大小、idle 停止、`.mat` log 選項；**右側兩張 live chart**：BER vs bucket（semilog y）+ SNR vs bucket。
* **Mode sweep**：文字框輸入 `9,10,11` 即可在按一次 Start 後連跑多個 mode（unique + stable order）。
* **Snapshot**：一鍵把所有開著的 figure（uifigure / timescope / spectrumAnalyzer / ConstellationDiagram / dashboard）全部 `exportgraphics` 成 PNG，存到 `snapshots_YYYYMMDD_HHMMSS/` 資料夾。
* **Dry run**：勾起來不需要 USRP，10× 加速時序驗證 UI（Start/Stop 是否即時、進度 label 是否更新、validation 錯誤訊息是否清楚）。

### ⚠ 已知未驗證
這套程式碼**只跑過 dry-run path，還沒上 USRP smoke test**。預期可能踩到的雷：
* USRP TX pipeline 對「ch1 突然從 frame 變零再變回 frame」的 underrun 行為。
* 真實 RX 收到的 frame 間隔抖動會不會讓「gap > 0.5 × expectedOff」的推斷誤觸發 / 漏觸發。
* mode 9/10/11/12 在 burst 模式下 jammer 只建一次重用是否真的跟連續模式等價。
* GUI 主迴圈 `drawnow limitrate` 是否在 USRP 高 frame rate 下搶 CPU 造成 underrun。

下次帶設備跑時建議的 smoke test：先 `mode=0`（baseline）+ `pattern='continuous'` 確認 burst TX 自己會送、會停；再 `mode=8`（broadband）+ `pattern='single_shot'`，看 RX 端的 BER 曲線在指定 burst 是否真的爆。

## 系統需求與執行方式
1.  **硬體支援:** USRP B210 (TX端) 與 USRP N200/N210 (RX端)。
2.  **軟體需求:** MATLAB (需安裝 Communications Toolbox, DSP System Toolbox, USRP Support Package)。
3.  **執行步驟（建議使用 `OFDM_Jammer_Project/`）:**
    * 在 RX 機器開啟一個 MATLAB 視窗：`cd OFDM_Jammer_Project; rx_console()`，等待印出「Warm-up done」。
    * 在 TX 機器另開一個 MATLAB 視窗：`cd OFDM_Jammer_Project; tx_console()` 跑完整 22 階段 sweep，或 `tx_console(7, 2)` 鎖定 TODO8 flower 並把功率拉到 2 倍。
    * 在 Monitor 視窗觀測各階段攻擊對 SNR / BER / 偵測率 / 星座圖的即時影響。
    * 不需要硬體就想驗證所有攻擊模式的數位行為時：`cd OFDM_Jammer_Project; selftest`（loopback parity check）。
4.  **舊版執行方式（`jam_experiment/`，保留中）:** 與上面對應 — 先跑 `jam_experiment/jam_monitor.m`，再跑 `jam_experiment/jam_tx.m`。新舊兩份保持參數一致，但建議新實驗從 `OFDM_Jammer_Project/` 開始。
5.  **排程對齊:** 在 `OFDM_Jammer_Project/` 中，TX/RX 共用 `config/load_parameters.m` 與 `modes/mode_registry.m`，所以 `cfg.secondsPerPhase`、`modeTypes`、`modeBwIdxs` 等過去要手抄一致的欄位已不需要再手動同步；只要記得 `params.sched.runSeconds` 須 ≥ 排程總長 (預設 480 s ≥ 22 × 20 s)。

## 目前進度與 TODO (Future Work)
* [x] OFDM 框架搭建與收發同步。
* [x] 結構化實體層攻擊 (TODO2 ~ TODO8) 實作與整合。
* [x] 寬頻 / 限頻 / CW / 假 frame 覆蓋攻擊 (TODO9 ~ TODO12) 實作與整合。
* [x] mode 9 (限頻 AWGN) 自動 BW sweep 機制。
* [x] 發送端 (TX) 的 CRC-16 ECC 封裝雛形（`jammer1.m` 沙盒 → 已整合至 `OFDM_Jammer_Project/core/compute_crc16.m`）。
* [x] 重構為 `OFDM_Jammer_Project/`：參數驅動、單一來源 spec、每個攻擊一檔（TX build + RX rxcfg），杜絕舊架構 TX/RX 三陣列手動同步的踩雷。
* [x] `selftest.m` 數位 loopback parity check（22 階段全跑、無需硬體）。
* [x] **Burst-mode 排程 harness + GUI apps**（`tx_burst_console` / `rx_burst_console` / `tx_burst_app` / `rx_burst_app`）— duty-cycle TX、5 種 jammer 觸發 pattern、桶式 SNR/BER 累積、TX burst 索引推斷、live BER/SNR 圖、preset save/load、全 figure 一鍵截圖、`.mat` log。
* [ ] **硬體 parity 驗收。** OFDM_Jammer_Project 在 USRP 上跑出與 `jam_experiment/` 同等行為後，移除舊版資料夾。
* [ ] **Burst-mode hardware smoke test。** 上述新 harness 僅做過 code review + dry-run path，**未在實際 USRP 上實跑**，預期會踩到 frame timing / USRP pipeline / mode 互動的 bug。
* [ ] **待完成：CRC-16 端到端整合。** TX 目前仍未把 CRC 附在 frame 內；core 已備好 `compute_crc16`，待 `build_frame` 與 `process_capture` 串接後啟用驗證。
* [ ] 對抗 jammer 的調適性策略 (例如 frequency hopping、interleaving + FEC) 與量化評估。