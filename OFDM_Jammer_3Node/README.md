# OFDM_Jammer_3Node — three-radio A→B attacked by C

Realistic topology: **A transmits to B, attacked by an unknown C**, on **three
separate N210 USRPs**. Parallel to (and reusing) `../OFDM_Jammer_Project/`.

```
USRP2 (A)  --- clean OFDM frame --->  USRP1 (B)  victim receiver
                                          ^
                          jam (over the air)
                                          |
                      USRP3 (C)  reactive jammer (sense-then-jam, TDD)
```

## Why a new project

The 2-node `OFDM_Jammer_Project` puts the real frame and the jammer on **two
channels of one B210**, so they share a clock/buffer and the jammer is
**sample-aligned** to the victim frame — that is what makes the structured
attacks (modes 1–7,12) hit exact sample positions. Splitting A and C onto
**independent radios removes that alignment**. This project keeps the 2-node
path untouched and adds only the device/topology layer; all waveform and
attack logic is **reused** from `OFDM_Jammer_Project/core` + `modes`.

## Layout

```
OFDM_Jammer_3Node/
├── tx_A_console.m          ENTRY (USRP2): clean continuous OFDM TX
├── rx_B_console.m          ENTRY (USRP1): victim monitor (dashboard/SNR/BER)
├── jammer_C_console.m      ENTRY (USRP3): reactive sense→jam (TDD)
├── selftest_3node.m        offline 3-node simulation (no radio)
├── init_n210_tx.m / init_n210_rx.m   param-driven single-channel N210 init
├── add_paths_3node.m       puts 3-node + reused 2-node code on path
├── config/
│   └── load_parameters_3node.m   3× N210 cfg + shared rf + reactive knobs
└── scripts/
    ├── run_tx_A.m          single-channel continuous TX loop
    ├── run_rx_B.m          victim RX loop (adapted from run_rx_loop)
    └── run_jammer_C.m      reactive TDD loop: sense → detect → jam burst
```

## Setup

1. Three N210s on one subnet with **distinct IPs**, host NIC reachable.
2. Edit [config/load_parameters_3node.m](config/load_parameters_3node.m):
   - `params.A.ipAddress`, `params.B.ipAddress`, `params.C.tx/rx.ipAddress`
     (C's tx and rx share one IP — it is one radio).
   - All nodes must agree on `params.rf.fc` and `params.rf.fs`.
3. `../OFDM_Jammer_Project/` must sit next to this folder (reused by path).

## Usage

Run each on the host wired to that radio (separate MATLAB sessions):

```matlab
% USRP1 (victim) — start first
cd OFDM_Jammer_3Node;  rx_B_console

% USRP2 (legitimate sender)
cd OFDM_Jammer_3Node;  tx_A_console

% USRP3 (attacker)
cd OFDM_Jammer_3Node;  jammer_C_console            % defaults (mode 8, reactive)
jammer_C_console(8)                                % broadband
jammer_C_console(8, 2)                             % + 2× digital power
jammer_C_console(10, 1, false)                     % single CW, periodic (no sense)
```

JSR at B is set primarily by `params.C.tx.gain` (hardware), with
`power` as a secondary digital knob. Reactive vs periodic and all timing
knobs live under `params.C.react`.

## How reactive C works (and its limit)

One N210 cannot transmit and receive simultaneously in MATLAB, so C is
**listen-then-talk (TDD)**: sense A's preamble with the RX object → if the
channel is busy, release RX, open TX, stream the jammer for `jamBursts`
frames → sense again. Because of the release/setup switch, **C jams the
frames *after* the one it sensed** (A transmits continuously, so "jam while
busy" still works statistically). If switching latency is too high, set
`params.C.react.reactive = false` for a periodic duty-cycled jammer.

## What works in 3-node vs 2-node

- **Alignment-free** (8 broadband, 9 band-limited AWGN, 10/11 CW, noise
  overlays): behave as in 2-node — the meaningful attacks here.
- **Structured** (1–7, 12): **best-effort only**. C builds them from a
  reference frame (it knows A's spec/seed, not A's on-air timing) and times
  them coarsely off its own detection; they degrade toward the clean baseline
  at B because per-sample placement no longer lines up.

## Verification

1. **Offline first (no radio):** `selftest_3node` — simulates B's over-air
   sum with a **random delay + CFO** on the jammer (breaks alignment) and
   prints detect/BER/SNR per mode. Confirms alignment-free modes still bite,
   structured modes degrade. Try `selftest_3node(12, 5e3)` for higher JSR/CFO.
2. **Per-radio bring-up:** ping each N210; run `tx_A_console` + `rx_B_console`
   with C idle → B shows `LINK OK`, BER≈0.
3. **Add jammer (alignment-free):** `jammer_C_console(8,1,false)` continuous →
   B flips to `JAMMING DETECTED`, BER↑. Sweep `params.C.tx.gain` for JSR vs BER.
4. **Reactive:** `jammer_C_console(8)` → C only fires while A is active (watch
   C's `sense → FIRE` log and B's intermittent degradation).
5. **Structured best-effort:** `jammer_C_console(7)` / `(10)` / `(11)` → expect
   partial/statistical effect; note the difference from the 2-node demo.
