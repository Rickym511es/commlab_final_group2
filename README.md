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
├── selftest.m                    digital loopback parity check (no hardware)
│
├── config/
│   └── load_parameters.m         single source of truth: spec / tx / rx
│                                 / sched / detect / knob
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
│   └── make_dashboard.m / update_dashboard.m
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
    ├── run_tx_loop.m             TX while-loop body
    └── run_rx_loop.m             RX while-loop body
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
參照論文 *Jamming Attacks and Anti-Jamming Strategies in Wireless Networks*；經整理後目前的攻擊清單（共 **17 個排程階段**）：

每個攻擊區分 **type 1 = noise 變體**（在目標區段灌高斯複數雜訊）與 **type 2 = structured 變體**（注入特定 OFDM 物件，例如假 STS / 假 LTS / flower）。下表標示每個 mode 還剩下哪些 type。

| Mode | 標籤 | type 1 | type 2 | 備註 |
|---|---|:-:|:-:|---|
| 0 | NO ATTACK | — | — | baseline，用來校正 RX 的 baselineSNR |
| 1 | TODO2 STS 時間同步攻擊 | ✓ | ✓ | type 2 為偏移 +64 樣本的假 STS |
| 2 | TODO3 STS 粗 CFO 攻擊 | — | ✓ | type 2: 真 STS 加 80 kHz CFO |
| 3 | TODO4 LTS 細 CFO 攻擊 | ✓ | ✓ | 只攻擊 copy1，留 copy2 給 RX 估通道 |
| 4 | TODO5 pilot 攻擊 | ✓ | — | 在 4 條 pilot 子載波灌雜訊 |
| 5 | TODO6 LTS 通道估計攻擊 | ✓ | ✓ | type 2: 假 LTS 每隔一條 active subcarrier 反相；RX 端 `equalize_symbol` 改用 MMSE 正則化避免 H≈0 的 bin 除零爆炸 |
| 6 | TODO7 CP 循環卷積攻擊 | ✓ | ✓ | type 2: CP 換成不相關 OFDM body 開頭 |
| 7 | TODO8 Flower 覆蓋 | — | ✓ | rose-curve 高功率資料覆蓋（可由 `knob.flower_petals` 調花瓣數）|
| 8 | TODO9 Broadband 雜訊 | — | ✓ | 全 frame 全頻段 AWGN；強度=外部 `power` 參數 |
| 9 | TODO9-2 限頻 AWGN | — | ✓ | `bw_ratio` 由 `tx_console(9,power,'bw_ratio',x)` 設定 |
| 10 | TODO10 單頻 CW | — | ✓ | 頻率由 `'freq', f` 覆寫 |
| 11 | TODO11 多頻 CW | — | ✓ | 頻率組與振幅由 `'freqs', F, 'amps', A` 覆寫 |
| 12 | TODO12 假 Frame 覆蓋 | — | ✓ | 獨立 seed 重新產生完整 [pad;STS;LTS;OFDM;pad] |

干擾強度由 `tx_console(mode, power, ...)` 的 `power` 參數統一控制：內部會同時設定 `knob.noise_power` 與 `knob.jam_power_scale`，最終以 victim RMS 倍數做 whole-frame 正規化。各 mode 的形狀參數（mode 9 的 `bw_ratio`、mode 10 的 `freq`、mode 11 的 `freqs/amps`）也都可以從 console 用 name-value 一次覆寫，不需動 `load_parameters.m`。

### Console 範例
```matlab
tx_console()                                  % 跑完整 16 階段 sweep
tx_console(7, 2)                              % 鎖定 flower、功率 2x
tx_console(8, 1.5)                            % 鎖定 broadband、功率 1.5x
tx_console(9, 1, 'bw_ratio', 0.3)             % 限頻 AWGN：bw=0.3
tx_console(10, 1, 'freq', 200e3)              % 單頻 CW @ 200 kHz
tx_console(11, 1, 'freqs', [80e3 160e3], ...
                  'amps',  [1 1])             % 兩條等強度自選頻率
```

## 系統需求與執行方式
1.  **硬體支援:** USRP B210 (TX端) 與 USRP N200/N210 (RX端)。
2.  **軟體需求:** MATLAB (需安裝 Communications Toolbox, DSP System Toolbox, USRP Support Package)。
3.  **執行步驟（建議使用 `OFDM_Jammer_Project/`）:**
    * 在 RX 機器開啟一個 MATLAB 視窗：`cd OFDM_Jammer_Project; rx_console()`，等待印出「Warm-up done」。
    * 在 TX 機器另開一個 MATLAB 視窗：`cd OFDM_Jammer_Project; tx_console()` 跑完整 16 階段 sweep，或 `tx_console(7, 2)` 鎖定 TODO8 flower 並把功率拉到 2 倍。
    * 在 Monitor 視窗觀測各階段攻擊對 SNR / BER / 偵測率 / 星座圖的即時影響。
    * 不需要硬體就想驗證所有攻擊模式的數位行為時：`cd OFDM_Jammer_Project; selftest`（loopback parity check）。
4.  **舊版執行方式（`jam_experiment/`，保留中）:** 與上面對應 — 先跑 `jam_experiment/jam_monitor.m`，再跑 `jam_experiment/jam_tx.m`。新舊兩份保持參數一致，但建議新實驗從 `OFDM_Jammer_Project/` 開始。
5.  **排程對齊:** 在 `OFDM_Jammer_Project/` 中，TX/RX 共用 `config/load_parameters.m` 與 `modes/mode_registry.m`，所以 `cfg.secondsPerPhase`、`modeTypes`、`modeBwIdxs` 等過去要手抄一致的欄位已不需要再手動同步；只要記得 `params.sched.runSeconds` 須 ≥ 排程總長 (預設 480 s ≥ 17 × 20 s = 340 s)。

## 目前進度與 TODO (Future Work)
* [x] OFDM 框架搭建與收發同步。
* [x] 結構化實體層攻擊 (TODO2 ~ TODO8) 實作與整合。
* [x] 寬頻 / 限頻 / CW / 假 frame 覆蓋攻擊 (TODO9 ~ TODO12) 實作與整合。
* [x] mode 9 (限頻 AWGN) 帶寬可由 console name-value 即時指定 (`'bw_ratio', x`)，取代原本的硬編碼 sweep 陣列。
* [x] mode 10 / 11 的目標頻率（單頻 / 多頻 CW）可由 console name-value 覆寫 (`'freq', f` / `'freqs', F, 'amps', A`)。
* [x] 模組精簡：移除 mode 4 結構化變體、mode 7 雜訊變體、mode 8 雙變體合併成單一強度可調 broadband；mode 5 結構化變體保留，並以 RX 端 MMSE 正則化處理 H≈0 的爆炸；排程從 22 → 17 階段。
* [x] RX 等化器升級：`equalize_symbol` 改成 MMSE 正則化（`x = Y·conj(H)/(|H|² + ε)`，ε 隨 median(|H|) 自適應），對乾淨通道仍是 ZF 行為，對 H≈0 的 bin 自動視為軟抹除。
* [x] 發送端 (TX) 的 CRC-16 ECC 封裝雛形（`jammer1.m` 沙盒 → 已整合至 `OFDM_Jammer_Project/core/compute_crc16.m`）。
* [x] 重構為 `OFDM_Jammer_Project/`：參數驅動、單一來源 spec、每個攻擊一檔（TX build + RX rxcfg），杜絕舊架構 TX/RX 三陣列手動同步的踩雷。
* [x] `selftest.m` 數位 loopback parity check（16 階段全跑、無需硬體）。
* [ ] **硬體 parity 驗收。** OFDM_Jammer_Project 在 USRP 上跑出與 `jam_experiment/` 同等行為後，移除舊版資料夾。
* [ ] **待完成：CRC-16 端到端整合。** TX 目前仍未把 CRC 附在 frame 內；core 已備好 `compute_crc16`，待 `build_frame` 與 `process_capture` 串接後啟用驗證。
* [ ] 對抗 jammer 的調適性策略 (例如 frequency hopping、interleaving + FEC) 與量化評估。