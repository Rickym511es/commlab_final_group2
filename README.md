# MATLAB OFDM Jamming & Anti-Jamming Project

## 專案簡介
本專案基於 MATLAB 與 USRP (軟體定義無線電)，實作了一個完整的 802.11a/g OFDM 收發系統，並針對 OFDM 實體層 (PHY Layer) 的各個脆弱點，開發了 12 種無線電干擾 (Jamming) 攻擊模型（從結構化的 preamble/pilot/CP 注入，到寬頻 / 限頻 / 單頻 / 多頻 CW / 假 frame 覆蓋）。接收端具備即時的鏈路品質監看、干擾偵測與 CRC 完整性驗證。本專案可用於評估無線通訊網路在惡意干擾下的穩健性，並測試未來的防禦 (Anti-jamming) 策略。

## 檔案結構
* **基礎收發框架**
    * `usrp_ofdm_tx.m`: 純淨 OFDM 封包發射器 (Baseline)。
    * `usrp_ofdm_monitor.m`: OFDM 接收器與監看儀表板，提供頻譜、星座圖、SNR 與 BER 即時顯示。
* **干擾與實驗自動化** (`jam_experiment/`)
    * `jam_tx.m`: 實驗發射端主程式。B210 雙通道發射 (Ch1 真實訊號 / Ch2 干擾訊號)，依時間排程自動切換 12 種攻擊；mode 9 (限頻 AWGN) 會自動 sweep `knob.awgn_bw_ratio` 中所有設定的頻寬比例，總共產生約 22 個階段 (含 baseline)。
    * `jam_monitor.m`: 實驗接收端主程式 (N210)。配備進階的干擾偵測邏輯 (偵測 SNR 驟降、偵測率下降、BER 飆升)、CRC-16 完整性驗證，並能觀測干擾造成的星座圖潰散或特定簽名 (如 Flower 圖案)。
* **演算法核心**
    * `jammer1.m`: 干擾與防禦機制的原型開發沙盒，包含主要實體層攻擊模型的數學生成邏輯與實驗性 CRC-16 封裝。

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

## 系統需求與執行方式
1.  **硬體支援:** USRP B210 (TX端) 與 USRP N200/N210 (RX端)。
2.  **軟體需求:** MATLAB (需安裝 Communications Toolbox, DSP System Toolbox, USRP Support Package)。
3.  **執行步驟:**
    * 開啟一個 MATLAB 視窗，執行 `jam_experiment/jam_monitor.m`。等待終端機顯示「暖機完成」。
    * 開啟另一個 MATLAB 視窗，執行 `jam_experiment/jam_tx.m` 開始發送排程攻擊。
    * 在 Monitor 視窗觀測各階段攻擊對通訊鏈路的即時影響、CRC 通過率與 SNR/BER 變化。
4.  **排程對齊注意事項:** `jam_tx.m` 與 `jam_monitor.m` 內的 `cfg.secondsPerPhase`、`modeTypes`、`modeBwIdxs` / `modeBwCount` 必須維持一致；`cfg.runSeconds` 須 ≥ jam_tx 排程總長 (目前 ≥ 440s)。

## 目前進度與 TODO (Future Work)
* [x] OFDM 框架搭建與收發同步。
* [x] 結構化實體層攻擊 (TODO2 ~ TODO8) 實作與整合。
* [x] 寬頻 / 限頻 / CW / 假 frame 覆蓋攻擊 (TODO9 ~ TODO12) 實作與整合。
* [x] mode 9 (限頻 AWGN) 自動 BW sweep 機制。
* [x] 發送端 (TX) 的 ECC (CRC-16) 防禦封裝設計。
* [x] 接收端 (RX) 的 CRC-16 完整性驗證邏輯。
* [ ] 對抗 jammer 的調適性策略 (例如 frequency hopping、interleaving + FEC) 與量化評估。