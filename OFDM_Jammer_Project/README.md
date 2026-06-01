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
├── selftest.m                    數位 loopback parity check(免硬體)
│
├── config/
│   └── load_parameters.m         單一來源:spec / tx / rx / sched / detect / knob
│
├── core/                         TX/RX 共用底層
│   ├── gen_sts.m / gen_lts.m
│   ├── gen_ofdm_symbol.m / gen_ofdm_data.m
│   ├── build_frame.m / frame_info.m
│   ├── process_capture.m         RX: detect → CFO → H → demod → BER/SNR
│   ├── detect_sts_mf.m / detect_sts_autocorr.m
│   ├── estimate_channel.m / ofdm_demod_symbol.m / equalize_symbol.m (MMSE)
│   ├── init_usrp_tx.m / init_usrp_rx.m
│   ├── compute_crc16.m           CRC-16-CCITT
│   ├── apply_knob_overrides.m    console name-value 覆寫解析
│   ├── normalize_jammer.m / default_rxcfg.m / feed_jam_const.m
│   └── make_dashboard.m / update_dashboard.m
│
├── modes/                        每個攻擊一檔:TX build + RX rxcfg
│   ├── mode00_baseline.m … mode12_fake_frame.m
│   └── mode_registry.m           把 (mode × type × sweep) 展開成排程
│
└── scripts/
    ├── run_tx_loop.m             TX while 迴圈
    └── run_rx_loop.m             RX while 迴圈
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

## 進度(本專案)

* [x] OFDM 框架搭建與收發同步。
* [x] 結構化(TODO2–8)+ 寬頻 / 限頻 / CW / 假 frame(TODO9–12)攻擊整合。
* [x] mode 9/10/11 形狀參數改由 console name-value 即時指定,取代硬編碼 sweep。
* [x] 模組精簡(22 → 17 階段)+ RX MMSE 等化器(`x = Y·conj(H)/(|H|²+ε)`)處理 H≈0 爆炸。
* [x] `selftest.m` 數位 loopback parity check(免硬體)。
* [ ] 硬體 parity 驗收(對照 `../jam_experiment/`)後退役舊版。
* [ ] CRC-16 端到端整合(`compute_crc16` 已備,待串接 `build_frame` / `process_capture`)。
