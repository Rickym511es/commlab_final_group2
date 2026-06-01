# OFDM_Jammer_3Node — 三台獨立電台 (A→B 被 C 攻擊)

真實場景拓樸:**A 傳給 B,被一個未知的 C 攻擊**,跑在**三台獨立的 N210** 上。本資料夾與 [`../OFDM_Jammer_Project/`](../OFDM_Jammer_Project/) 平行,並沿用其程式;總覽見 [`../README.md`](../README.md)。

```
USRP2 (A)  --- clean OFDM frame ------------>  USRP1 (B)  victim receiver
                                       ^
                                       |
                          jam (over the air)
                                       |
                      USRP3 (C)  reactive jammer (sense-then-jam, TDD)
```

## 為什麼另開一個專案

2-node 的 `OFDM_Jammer_Project` 把真實 frame 與 jammer 放在**同一台 B210 的兩個通道**,共用時脈 / buffer,所以 jammer 與 victim frame 是 **sample 對齊**的 —— 這是結構化攻擊(modes 1–7,12)能打中精確 sample 位置的前提。把 A 與 C 拆成**獨立電台後,這個對齊就消失了**。本專案保留 2-node 路徑不動,只新增「裝置 / 拓樸層」;所有波形與攻擊邏輯**沿用** `OFDM_Jammer_Project/core` + `modes`。

## 檔案結構

```
OFDM_Jammer_3Node/
├── tx_A_console.m          ENTRY (USRP2):乾淨連續 OFDM TX
├── rx_B_console.m          ENTRY (USRP1):victim 監看 (dashboard/SNR/BER)
├── jammer_C_console.m      ENTRY (USRP3):reactive 感測→干擾 (TDD)
├── selftest_3node.m        離線 3-node 模擬 (免硬體)
├── init_n210_tx.m / init_n210_rx.m   參數化單通道 N210 init
├── add_paths_3node.m       把 3-node + 沿用的 2-node 程式掛上路徑
├── config/
│   └── load_parameters_3node.m   3× N210 設定 + 共用 rf + reactive knobs
└── scripts/
    ├── run_tx_A.m          單通道連續 TX 迴圈
    ├── run_rx_B.m          victim RX 迴圈 (改自 run_rx_loop)
    └── run_jammer_C.m      reactive TDD 迴圈:sense → detect → jam burst
```

## 設定

1. 三台 N210 在同一子網、**IP 各自不同**、主機網卡可達。
2. 編輯 [config/load_parameters_3node.m](config/load_parameters_3node.m):
   - `params.A.ipAddress`、`params.B.ipAddress`、`params.C.tx/rx.ipAddress`
     (C 的 tx 與 rx 共用同一個 IP —— 它是同一台電台)。
   - 三個節點必須對齊 `params.rf.fc` 與 `params.rf.fs`。
3. `../OFDM_Jammer_Project/` 必須與本資料夾並排放(以路徑沿用)。

## 用法

在連到各電台的主機上分別開 MATLAB 視窗執行:

```matlab
% USRP1 (victim) — 先開
cd OFDM_Jammer_3Node;  rx_B_console

% USRP2 (合法發送端)
cd OFDM_Jammer_3Node;  tx_A_console

% USRP3 (攻擊者)
cd OFDM_Jammer_3Node;  jammer_C_console            % 預設 (mode 8、reactive)
jammer_C_console(8)                                % broadband
jammer_C_console(8, 2)                             % + 2x 數位功率
jammer_C_console(10, 1, false)                     % 單頻 CW、週期式 (不感測)
```

B 端的 JSR(干擾/訊號比)主要由 `params.C.tx.gain`(硬體增益)決定,`power` 是次要的數位旋鈕。reactive 開關與所有時序 knob 都在 `params.C.react` 底下。

## reactive C 怎麼運作(與它的限制)

一台 N210 在 MATLAB 裡無法同時收與發,所以 C 採 **聽-說輪替 (TDD)**:用 RX 物件感測 A 的 preamble → 若通道忙碌,釋放 RX、開 TX、把 jammer 串流 `jamBursts` 個 frame → 再回去感測。由於 release/setup 切換有延遲,**C 干擾的是它感測到的那個 frame 之後的 frame**(A 連續發送,所以「忙就打」統計上仍有效)。若切換延遲太大,把 `params.C.react.reactive = false` 改用週期式 duty-cycle 干擾。

## 3-node 與 2-node 的差異

- **對齊無關型**(8 broadband、9 限頻 AWGN、10/11 CW、noise overlay):行為與 2-node 相同 —— 這才是本拓樸下有意義的攻擊。
- **結構化型**(1–7, 12):**僅 best-effort**。C 用參考 frame 重建(它知道 A 的 spec/seed,但不知 A 的空中時序),並靠自己的偵測粗略對時;因為逐 sample 的位置在 B 對不齊,效果會趨近乾淨 baseline。

## 驗證

1. **先離線(免硬體):** `selftest_3node` —— 模擬 B 的空中疊加,對 jammer 加上**隨機 delay + CFO**(打破對齊),逐 mode 印出 detect/BER/SNR。確認對齊無關型仍咬得動、結構化型退化。可試 `selftest_3node(12, 5e3)` 拉高 JSR/CFO。
2. **逐台 bring-up:** ping 每台 N210;C idle 時跑 `tx_A_console` + `rx_B_console` → B 顯示 `LINK OK`、BER≈0。
3. **加 jammer(對齊無關):** `jammer_C_console(8,1,false)` 連續 → B 翻成 `JAMMING DETECTED`、BER↑。掃 `params.C.tx.gain` 看 JSR vs BER。
4. **reactive:** `jammer_C_console(8)` → C 只在 A 活躍時開打(看 C 的 `sense → FIRE` log 與 B 的間歇性劣化)。
5. **結構化 best-effort:** `jammer_C_console(7)` / `(10)` / `(11)` → 預期部分/統計性的效果;留意與 2-node demo 的差異。
