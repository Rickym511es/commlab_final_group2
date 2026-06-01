# OFDM_Jammer_Project — 單台雙通道 (2-node) 實驗

參數驅動的 OFDM 干擾實驗主架構。**一台 B210 用雙通道發射**(`ch1 = 真實 OFDM frame`、`ch2 = jammer`),**一台 N210 接收**。因為兩個訊號出自同一台裝置 / 同一時脈 / 同一 buffer,jammer 與 victim frame 是 **sample 對齊**的 —— 這是結構化攻擊(STS/LTS/pilot/CP,modes 1–7,12)能打中精確 sample 位置的前提。

> 三台獨立電台(A→B 被獨立 C 攻擊)的版本見 [`../OFDM_Jammer_3Node/`](../OFDM_Jammer_3Node/);共用的攻擊與波形邏輯(`core/` + `modes/`)由本資料夾提供。

## 檔案結構

```
OFDM_Jammer_Project/
├── tx_console.m                  ENTRY (B210): 預設跑完整 sweep;
│                                              tx_console(mode, power, ...) 鎖定單一攻擊
├── rx_console.m                  ENTRY (N210): 預設監看完整 sweep;
│                                              rx_console(mode, ...) 鎖定 RX 策略
├── tx_burst_console.m            ENTRY (B210, burst mode): duty-cycled TX +
│                                              5 種 jammer 觸發 pattern
├── rx_burst_console.m            ENTRY (N210, burst mode): 桶式 SNR/BER
│                                              + TX burst 索引推斷 + .mat log
├── tx_burst_app.m / rx_burst_app.m  GUI 前端(uifigure,git 友善)
├── selftest.m                    數位 loopback parity check(免硬體)
│
├── config/
│   ├── load_parameters.m         單一來源:spec / tx / rx / sched / detect / knob
│   └── default_burst_opts.m      burst 排程預設(duty cycle、jammer pattern、bucket size…)
│
├── core/                         TX/RX 共用底層
│   ├── gen_sts.m / gen_lts.m
│   ├── gen_ofdm_symbol.m / gen_ofdm_data.m
│   ├── build_frame.m / frame_info.m
│   ├── process_capture.m         RX: detect → CFO → H → demod → BER/SNR + CRC
│   ├── detect_sts_mf.m / detect_sts_autocorr.m
│   ├── estimate_channel.m / ofdm_demod_symbol.m / equalize_symbol.m (MMSE)
│   ├── init_usrp_tx.m / init_usrp_rx.m
│   ├── compute_crc16.m           CRC-16-CCITT(實 frame 整合)
│   ├── gen_lorawan_frame.m       LoRaWAN 1.0.x data PHYPayload helper
│   ├── apply_knob_overrides.m    console name-value 覆寫解析
│   ├── normalize_jammer.m / default_rxcfg.m / feed_jam_const.m
│   ├── make_dashboard.m / update_dashboard.m
│   └── snapshot_figs.m           一鍵把所有開著的 figure dump 成 PNG(GUI 用)
│
├── modes/                        每個攻擊一檔:TX build + RX rxcfg
│   ├── mode00_baseline.m … mode12_fake_frame.m
│   └── mode_registry.m           把 (mode × type × sweep) 展開成排程
│
└── scripts/
    ├── run_tx_loop.m / run_rx_loop.m     full-sweep while 迴圈
    └── run_tx_burst.m / run_rx_burst.m   burst-mode 迴圈(GUI Stop / 進度 hook)
```

## 各層說明

* **`config/load_parameters.m`**:全部硬體 / OFDM spec / 排程 / 偵測門檻 / 功率 knob 的單一來源,杜絕「兩支腳本 spec 必須完全一致」的踩雷。
* **`core/`**:訊號產生(`gen_sts/lts/ofdm_*`)、frame 組裝(`build_frame`, `frame_info`)、接收鏈(`process_capture` + 兩種 STS 偵測器 + 通道估計 + MMSE 等化)、USRP 包裝、CRC-16-CCITT、儀表板。
* **`modes/mode00..mode12.m`**:每個攻擊獨立一檔,同時擁有自己的 TX `build` 與 RX `rxcfg`;`mode_registry.m` 把 (mode × type × sweep) 展開成排程,解決 TX/RX 三陣列手動同步的問題。
* **`scripts/run_tx_loop.m` / `run_rx_loop.m`**:主 while 迴圈,吃 params + schedule + USRP handle。
* **`selftest.m`**:數位 loopback parity check(免硬體)— 對每個排程階段建 jammer + 跑 `process_capture`,輸出 detect / BER / SNR。

## 攻擊模式列表

參照論文 *Jamming Attacks and Anti-Jamming Strategies in Wireless Networks*;整理後共 **17 個排程階段**:

**A. 結構化攻擊(針對 OFDM 同步／估計鏈路特定環節):**

| id | 名稱 | 說明 |
|---|---|---|
| 0 | NO ATTACK | 基線傳輸 |
| 1 | STS 時間同步 (TODO2) | 錯置封包起點 |
| 2 | STS 粗頻偏 CFO (TODO3) | 注入虛假 coarse CFO |
| 3 | LTS 細頻偏 CFO (TODO4) | 只攻擊 LTS copy1,留 copy2 給 RX 估通道 |
| 4 | Pilot CFO (TODO5) | 干擾導護子載波 |
| 5 | LTS 通道估計 (TODO6) | 破壞等化器 H 估計 |
| 6 | CP 循環卷積 (TODO7) | 錯誤 CP 引發 ISI |
| 7 | 高功率資料覆蓋 / Flower (TODO8) | data 子載波打花瓣狀星座 |

**B. 寬頻 / 限頻 / CW 攻擊(不依賴 OFDM 內部結構,泛用型):**

| id | 名稱 | 說明 |
|---|---|---|
| 8 | Broadband (TODO9) | 全頻段複數高斯雜訊,強度由 power 控制 |
| 9 | 限頻 AWGN (TODO9-2) | 只在 ±BW/2 注入,`'bw_ratio'` 可調 |
| 10 | 單頻 CW (TODO10) | `'freq'` 可調 |
| 11 | 多頻 CW (TODO11) | `'freqs'/'amps'` 可調 |
| 12 | 假 Frame 覆蓋 (TODO12) | 自訂 seed 重產 STS+LTS+OFDM data 整段對打 |

## Console 用法

| 指令 | 角色 | 行為 |
|---|---|---|
| `rx_console()` | N210 | 監看完整排程,依時間對齊各 phase |
| `rx_console(m, ...)` | N210 | 鎖定 mode `m` 的 RX 策略(鏡射同一組 name-value) |
| `tx_console()` | B210 | 完整 sweep(所有 mode × type × sweep) |
| `tx_console(m)` | B210 | 鎖定 mode `m`,預設功率 |
| `tx_console(m, p)` | B210 | 鎖定 mode `m`,功率 = victim RMS 的 `p` 倍 |
| `tx_console(m, p, name, value, …)` | B210 | 再覆寫形狀參數 |
| `selftest` | 離線 | 免硬體,逐階段建 jammer + 跑 `process_capture` |

`power` 同時設定 `knob.noise_power` 與 `knob.jam_power_scale`(victim 全 frame RMS 倍數)。形狀參數可由 console name-value 覆寫,不需動 `load_parameters.m`:`'bw_ratio'`(mode 9)、`'freq'`(mode 10)、`'freqs'/'amps'`(mode 11)。**單模式實驗務必 TX/RX 指定同一個 mode id。**

### 範例
```matlab
tx_console()                                  % 完整 17 階段 sweep
tx_console(7, 2)                              % flower,功率 2x
tx_console(8, 1.5)                            % broadband,功率 1.5x
tx_console(9, 1, 'bw_ratio', 0.3)             % 限頻 AWGN:bw=0.3
tx_console(10, 1, 'freq', 200e3)              % 單頻 CW @ 200 kHz
tx_console(11, 1, 'freqs', [80e3 160e3], ...
                  'amps',  [1 1])             % 兩條等強度自選頻率
```

## 執行方式

1. **硬體**:USRP B210(TX)+ USRP N200/N210(RX)。
2. **軟體**:MATLAB + Communications Toolbox、DSP System Toolbox、USRP Support Package。
3. **步驟**:
   * RX 機:`cd OFDM_Jammer_Project; rx_console()`,等印出「Warm-up done」。
   * TX 機:`cd OFDM_Jammer_Project; tx_console()`(或 `tx_console(7, 2)` 鎖定單一攻擊)。
   * Monitor 視窗觀測各階段對 SNR / BER / 偵測率 / 星座圖的即時影響。
   * 免硬體驗證:`cd OFDM_Jammer_Project; selftest`。
4. **排程對齊**:TX/RX 共用 `config/load_parameters.m` 與 `modes/mode_registry.m`,過去要手抄一致的欄位已不需手動同步;只要 `params.sched.runSeconds` ≥ 排程總長(預設 480 s ≥ 17 × 20 s = 340 s)。

## CRC + QPSK 端到端

為了讓「frame 是否受損」變成可量測的二值訊號,主鏈路做了兩項改動:

* **QAM 改成 QPSK (`spec.qam_num = 4`)**:constellation 點少且距離大,乾淨環境下 baseline BER ≈ 0,只要有任一 bit 翻轉 CRC 就能抓到,結果才有資訊量。
* **每個 frame 末尾附 CRC-16-CCITT**:`gen_ofdm_data` 先生成 `data_bits_per_frame = 1904` 個 user bits,呼叫 `compute_crc16` 算出 16 個 CRC bits,串成 `1920 = num_ofdm × num_data_sc × log2(qam_num)` 的完整 bit stream 再 QAM 調變。`process_capture` 在 demap 後切出最後 16 bits、對前段重新算 CRC、輸出 `res.crc_pass`。

CRC 結果在三條路徑都會出現:

* **`selftest.m`**:表格多一欄 `CRC` 顯示 `pass / fail / --`(`--` 代表沒偵測到 frame)。
* **`rx_console`(sweep)**:dashboard 多了「CRC pass (recent)」一列;jammed/link-OK 判定多吃一個門檻 `params.detect.crcPassJam`(預設 0.9);每 5 秒的 console log 也附 `CRC=<pct>`。
* **`rx_burst_console`**:每個 bucket 的列同時印 `SNR / BER / CRC=<pct>` 與 cumulative;`.mat` log 新增 `crcRate / totalCrcPass / cumCrcRate` 欄位。

預期讀數(直接照 `selftest` 跑出來的結果):

| 大類 | 例子 | CRC 預期 |
|---|---|---|
| Baseline | mode 0 | pass(BER=0、SNR≈120 dB)|
| 攻擊 preamble 但 RX 有對策 | mode 3(clean LTS copy)、mode 6 CP(無 multipath 時)| pass |
| 攻擊 preamble,RX 無法回復 | mode 1 STS noise(detector miss)、mode 2 coarse CFO | fail 或無 detect |
| 任何打到 data region 的攻擊 | mode 4/5/7/8/9/10/11/12 | fail(含「detected 但 BER ≫ 0」)|

(在 USRP 實機上 mode 6 預期會因實際 multipath 而變 fail,這就是與 digital loopback 的差別點。)

### Detector 補強
QPSK 的時域樣本量級比 16-QAM 均勻,導致 `detect_sts_autocorr` 在 frame 結尾的窗緣會出現 `|P|/R` 數值爆衝。修法:對 `Rseq` 加 5% 的相對 floor mask,能量太低的窗位直接視為無效。Baseline 偵測分數依舊 1.00,但 trailing-edge 的假峰被壓掉。

## LoRaWAN frame helper

`core/gen_lorawan_frame.m` 可產生 LoRaWAN 1.0.x data `PHYPayload`,組成為 `MHDR | FHDR | FPort | encrypted FRMPayload | MIC`。預設會產生 unconfirmed uplink frame,並用 LoRaWAN AES-128 payload encryption 與 AES-CMAC MIC 規則輸出 frame bytes、hex 字串,以及 MSB/LSB-first bit vectors。

```matlab
addpath(genpath('OFDM_Jammer_Project'));
[phyPayload, fields] = gen_lorawan_frame();
disp(fields.hex)
```

常用參數可透過 `opts` 傳入,例如 `mType`、`devAddr`、`fCnt`、`fPort`、`payload`、`nwkSKey`、`appSKey`、`fOpts`。目前 helper 產生的是 LoRaWAN MAC frame bytes,不是 LoRa chirp waveform。

## Burst-mode 排程實驗(**未在 USRP 上驗證**)

`tx_burst_console` / `rx_burst_console` 與 GUI 版本(`tx_burst_app` / `rx_burst_app`)是另一條獨立執行路徑,跟原本 sweep 完全分開。原本的 `tx_console` / `rx_console` / `run_tx_loop` / `run_rx_loop` 不受影響。

### 解決什麼問題
原本的 console 是「連續傳輸 + 連續 jammer」。burst 模式讓你可以:

* **TX 週期傳**:每個 burst 送 `framesPerBurst` 個 frame,然後沉默 `txPeriodFrames - framesPerBurst` 個 frame 的時間,可以乾淨地把每個 burst 當成一次獨立的「打靶」。
* **Jammer 5 種觸發 pattern**:
    * `'continuous'` — 一直開(舊行為)
    * `'periodic'` — 自己的週期,或對齊 TX duty
    * `'random'` — 每個 frame 獨立 Bernoulli
    * `'random_bursts'` — 每個 TX burst 一次 Bernoulli(整 burst 開或關)
    * `'single_shot'` — 只在指定 burst index 開火(demo「精準一擊」)
* **RX 桶式累積**:每收到 `rxFramesPerReport` 個 frame 結算一次平均 SNR/BER + 持續累積總計;沒有 TX/RX 時鐘同步,burst 邊界從「相鄰 detection 的時間差 > 預期 off 一半」推回去。
* **`.mat` log + offline 畫圖**:RX 結束自動存(`burst.logToMat=true`),可離線畫 BER vs bucket。
* **idle auto-stop**:TX 可能只跑十幾秒,RX 預設等 480s 太久 → 設 `rxAutoStopIdleSec` 自動結束。

### GUI(`tx_burst_app` / `rx_burst_app`)
* 純 `uifigure` 程式碼版(.m,git 友善),不是 App Designer .mlapp。
* TX 端:mode dropdown、pattern dropdown、burst 參數 spinner、power slider、Dry run checkbox、Save/Load preset、📸 Snapshot、Start/Stop。
* RX 端:同樣的選單 + RX 桶大小、idle 停止、`.mat` log 選項;**右側兩張 live chart**:BER vs bucket(semilog y)+ SNR vs bucket。
* **Mode sweep**:文字框輸入 `9,10,11` 即可在按一次 Start 後連跑多個 mode(unique + stable order)。
* **Snapshot**:一鍵把所有開著的 figure(uifigure / timescope / spectrumAnalyzer / ConstellationDiagram / dashboard)全部 `exportgraphics` 成 PNG,存到 `snapshots_YYYYMMDD_HHMMSS/`。
* **Dry run**:勾起來不需要 USRP,10× 加速時序驗證 UI(Start/Stop 是否即時、進度 label 是否更新、validation 錯誤訊息是否清楚)。

### ⚠ 已知未驗證
這套程式碼**只跑過 dry-run path,還沒上 USRP smoke test**。預期可能踩到的雷:
* USRP TX pipeline 對「ch1 突然從 frame 變零再變回 frame」的 underrun 行為。
* 真實 RX 收到的 frame 間隔抖動會不會讓「gap > 0.5 × expectedOff」的推斷誤觸發 / 漏觸發。
* mode 9/10/11/12 在 burst 模式下 jammer 只建一次重用是否真的跟連續模式等價。
* GUI 主迴圈 `drawnow limitrate` 是否在 USRP 高 frame rate 下搶 CPU 造成 underrun。

下次帶設備跑時建議的 smoke test:先 `mode=0`(baseline)+ `pattern='continuous'` 確認 burst TX 自己會送、會停;再 `mode=8`(broadband)+ `pattern='single_shot'`,看 RX 端的 BER 曲線在指定 burst 是否真的爆。

## 進度(本專案)

* [x] OFDM 框架搭建與收發同步。
* [x] 結構化(TODO2–8)+ 寬頻 / 限頻 / CW / 假 frame(TODO9–12)攻擊整合。
* [x] mode 9/10/11 形狀參數改由 console name-value 即時指定,取代硬編碼 sweep。
* [x] 模組精簡(22 → 17 階段)+ RX MMSE 等化器(`x = Y·conj(H)/(|H|²+ε)`)處理 H≈0 爆炸。
* [x] `selftest.m` 數位 loopback parity check(免硬體)。
* [x] CRC-16 端到端整合(payload 改 QPSK,`selftest` / `rx_console` / `rx_burst_console` 都報 CRC pass rate)。
* [x] Burst-mode 排程 harness + GUI apps(`tx/rx_burst_console` + `tx/rx_burst_app`)。
* [x] LoRaWAN frame helper(`gen_lorawan_frame.m`)。
* [ ] 硬體 parity 驗收(對照 `../jam_experiment/`)後退役舊版。
* [ ] Burst-mode 硬體 smoke test(目前只跑過 dry-run path)。
