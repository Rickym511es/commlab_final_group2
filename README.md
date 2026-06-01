# MATLAB OFDM Jamming & Anti-Jamming Project

## 專案簡介
本專案基於 MATLAB 與 USRP(軟體定義無線電),實作了一個完整的 802.11a/g OFDM 收發系統,並針對 OFDM 實體層(PHY Layer)的各個脆弱點開發了 **13 種干擾(Jamming)攻擊模型**(從結構化的 preamble / pilot / CP 注入,到寬頻 / 限頻 / 單頻 / 多頻 CW / 假 frame 覆蓋)。接收端具備即時的鏈路品質監看、干擾偵測與完整性驗證。可用於評估無線通訊在惡意干擾下的穩健性,並測試防禦(Anti-jamming)策略。

實驗有**兩種拓樸**,共用同一套波形與攻擊邏輯:

| | [`OFDM_Jammer_Project/`](OFDM_Jammer_Project/) | [`OFDM_Jammer_3Node/`](OFDM_Jammer_3Node/) |
|---|---|---|
| 拓樸 | 單台 **B210 雙通道** TX + N210 RX | 三台獨立 **N210**:A→B 被未知 C 攻擊 |
| 真實/jammer 關係 | 同一台、同時脈 → **sample 對齊** | 獨立電台 → **無對齊**(較真實) |
| 適用攻擊 | 全部 13 種(結構化可精準命中) | 對齊無關型(8/9/10/11+noise)為主;結構化為 best-effort |
| Jammer 行為 | 排程 sweep / 鎖定單一攻擊 | reactive 感測後干擾(TDD)或週期 |
| 用途 | 攻擊原理驗證、digital parity | 模擬「A 傳 B 被路人 C 干擾」的真實場景 |

兩者各有獨立 README,**從那裡開始跑實驗**:
- 2-node 詳細說明 → [OFDM_Jammer_Project/README.md](OFDM_Jammer_Project/README.md)
- 3-node 詳細說明 → [OFDM_Jammer_3Node/README.md](OFDM_Jammer_3Node/README.md)

## Repo 結構

```
commlab_final_group2/
├── OFDM_Jammer_Project/     主架構(2-node):waveform + 13 attacks + core/modes 的單一來源
├── OFDM_Jammer_3Node/       三台 N210(A→B 被 C 攻擊);沿用上面的 core/ + modes/
├── jam_experiment/          重構前歷史版本(jam_tx.m / jam_monitor.m),保留至 parity 驗收
├── comprehensive-jamming-strategy.pdf   目標論文
└── README.md                (本檔)總覽
```

## 共用設計:單一來源

攻擊與波形的核心邏輯只存在一處 —— `OFDM_Jammer_Project/` 的 `core/`(訊號產生、frame 組裝、接收鏈、偵測、等化、CRC、儀表板)與 `modes/`(每個攻擊一檔:TX `build` + RX `rxcfg`,由 `mode_registry` 展開排程)。

`OFDM_Jammer_3Node/` **不複製**這些,而是用 `add_paths_3node.m` 把相鄰的 `OFDM_Jammer_Project` 掛上路徑後直接重用,只新增「裝置 / 拓樸層」(三台 N210 設定、單通道 init、A/B/C 三個 console、reactive TDD 迴圈)。因此兩個資料夾**必須並排放**,且攻擊邏輯永不 drift。

## 其他檔案

* **`jam_experiment/`**:重構前的 TX/RX 腳本(`jam_tx.m`, `jam_monitor.m`),功能與 `OFDM_Jammer_Project` 等價,但 helpers / spec / 排程都是手抄複製。保留作回歸對照,parity 驗收後退役。
* **基礎收發框架**(Lab 原版):`usrp_ofdm_tx.m`(純淨 OFDM 發射)、`usrp_ofdm_monitor.m`(接收監看)。
* **`jammer1.m`**:干擾 / 防禦原型沙盒;邏輯已併入 `OFDM_Jammer_Project/core/`,保留以利對照。

## 系統需求

1. **硬體**:2-node 需 USRP B210(TX)+ N200/N210(RX);3-node 需三台 N210。
2. **軟體**:MATLAB + Communications Toolbox、DSP System Toolbox、USRP Support Package。
3. **快速上手**:
   * 攻擊原理 / 免硬體驗證 → 進 `OFDM_Jammer_Project/`,跑 `selftest`,再依其 README 上 B210+N210。
   * 真實三台場景 → 進 `OFDM_Jammer_3Node/`,先跑 `selftest_3node`(免硬體),再依其 README 設定三台 N210 的 IP 上機。

## 整體進度與 TODO (Future Work)
* [x] OFDM 框架搭建與收發同步。
* [x] 結構化(TODO2–8)+ 寬頻 / 限頻 / CW / 假 frame(TODO9–12)攻擊整合。
* [x] 重構為參數驅動的 `OFDM_Jammer_Project/`:單一來源 spec、每個攻擊一檔、`selftest` 數位 parity check。
* [x] mode 9/10/11 形狀參數改由 console name-value 即時指定;RX 升級 MMSE 等化器。
* [x] 新增三台獨立電台拓樸 `OFDM_Jammer_3Node/`:A→B 被未知 C 攻擊、reactive TDD jammer、`selftest_3node` 離線模擬(隨機 delay+CFO 打破對齊)。
* [ ] **硬體 parity 驗收**:`OFDM_Jammer_Project` 在 USRP 上跑出與 `jam_experiment/` 同等行為後,退役舊版。
* [ ] **3-node 上機驗證**:三台 N210 實測 reactive jammer;評估 TDD 切換延遲與對齊無關型攻擊的有效性。
* [ ] CRC-16 端到端整合(`compute_crc16` 已備,待串接 `build_frame` / `process_capture`)。
* [ ] 對抗 jammer 的調適性策略(frequency hopping、interleaving + FEC)與量化評估。
