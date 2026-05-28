# MATLAB OFDM Jamming & Anti-Jamming Project

## 專案簡介
本專案基於 MATLAB 與 USRP (軟體定義無線電)，實作了一個完整的 802.11a/g OFDM 收發系統，並針對 OFDM 實體層 (PHY Layer) 的各個脆弱點，開發了多種精密的無線電干擾 (Jamming) 攻擊模型。同時，接收端具備即時的鏈路品質監看與干擾偵測機制。本專案可用於評估無線通訊網路在惡意干擾下的穩健性，並測試未來的防禦 (Anti-jamming) 策略。

## 檔案結構
* **基礎收發框架**
    * `usrp_ofdm_tx.m`: 純淨 OFDM 封包發射器 (Baseline)。
    * `usrp_ofdm_monitor.m`: OFDM 接收器與監看儀表板，提供頻譜、星座圖、SNR 與 BER 即時顯示。
* **干擾與實驗自動化**
    * `jam_tx.m`: 實驗發射端主程式。支援雙通道發射 (Ch1 真實訊號 / Ch2 干擾訊號)，並根據時間排程自動切換 8 種不同的攻擊階段。
    * `jam_monitor.m`: 實驗接收端主程式。配備進階的干擾偵測邏輯 (偵測 SNR 驟降或 BER 攀升)，並能觀測干擾造成的星座圖潰散或特定簽名 (如 Flower 圖案)。
* **演算法核心**
    * `jammer1.m`: 干擾與防禦機制的原型開發沙盒。包含 7 種實體層攻擊模型的數學生成邏輯 (針對 STS, LTS, Pilot, CP, Data)，以及實驗性的 CRC-16 ECC 封裝防禦架構。

## 攻擊模式列表
此專案成功實作了以下實體層攻擊 (參照論文 *Jamming Attacks and Anti-Jamming Strategies in Wireless Networks* )：
1.  **NO ATTACK:** 基線傳輸。
2.  **STS 時間同步攻擊:** 錯置封包起點。
3.  **STS 粗頻偏 (CFO) 攻擊:** 注入虛假 CFO。
4.  **LTS 細頻偏 (CFO) 攻擊:** 破壞相位校正。
5.  **Pilot CFO 攻擊:** 單獨干擾導護子載波。
6.  **LTS 通道估計攻擊:** 破壞等化器 $H$ 矩陣估計。
7.  **CP 循環卷積攻擊:** 引發符號間干擾 (ISI)。
8.  **高功率覆蓋攻擊:** 於星座圖打出特定的 Flower 視覺干擾。

## 系統需求與執行方式
1.  **硬體支援:** USRP B210 (TX端) 與 USRP N200/N210 (RX端)。
2.  **軟體需求:** MATLAB (需安裝 Communications Toolbox, DSP System Toolbox, USRP Support Package)。
3.  **執行步驟:**
    * 開啟一個 MATLAB 視窗，執行 `jam_monitor.m`。等待終端機顯示「暖機完成」。
    * 開啟另一個 MATLAB 視窗，執行 `jam_tx.m` 開始發送排程攻擊。
    * 在 Monitor 視窗觀測各階段攻擊對通訊鏈路的即時影響。

## 目前進度與 TODO (Future Work)
* [x] OFDM 框架搭建與收發同步。
* [x] 所有實體層針對性攻擊演算法 (TODO2 ~ TODO8) 實作與整合。
* [x] 發送端 (TX) 的 ECC (CRC-16) 防禦封裝設計。
* [ ] **待完成：接收端 (RX) 的 CRC 驗證邏輯。** (需在接收端 QAM 解調後，取出最後 16 bits 與前面資料計算的 CRC 進行比對，作為丟棄受干擾封包的依據)。# commlab_final_group2