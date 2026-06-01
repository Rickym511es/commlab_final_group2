%% =====================================================================
%  usrp_ofdm_tx.m
%  OFDM 完整 frame 發射端（配合 usrp_ofdm_monitor.m）
%
%  發射的 frame 結構（與 Lab 5 一致）：
%    [pad] - [STS] - [LTS] - [OFDM data x num_ofdm] - [pad]
%    STS：frame 偵測用    LTS：通道估計用    pad：frame 之間的緩衝
%
%  關鍵：本檔的 spec 參數與 spec.seed 必須與 usrp_ofdm_monitor.m
%        「完全一致」，monitor 才能用相同 seed 重建 payload 來算 BER。
%
%  TX = B210 (USRP-2901)；RX = N200 (USRP-2920)。
%  兩支在不同 MATLAB 視窗各跑一份。先跑這支發射，再跑 monitor 接收。
%
%  需要：Communications Toolbox / DSP System Toolbox / USRP Support Package
% =====================================================================

clear; clc; close all;

%% ===== 使用者參數 ===================================================
cfg.serialNum       = '34D9DC3';     % B210 (USRP-2901) 的 SerialNum
cfg.fc              = 885e6;
cfg.fs              = 1e6;
cfg.gain            = 15;            % 太弱調高、星座爆掉調低
cfg.masterClockRate = 20e6;          % B210 可設定 master clock
cfg.runSeconds      = 300;
cfg.liveTxDisplay   = true;
cfg.displayEvery    = 20;

%% ===== Frame 規格（必須與 usrp_ofdm_monitor.m 完全一致）===========
spec.FFT_size  = 64;
spec.cp_size   = 16;
spec.active_sc = [-26:-1, 1:26];
spec.pilot_sc  = [-21 -7 7 21];
spec.qam_num   = 16;
spec.num_ofdm  = 20;
spec.pad_len   = 200;
spec.seed      = 12345;              % 固定種子：與 monitor 相同才能算 BER
spec.data_sc   = setdiff(spec.active_sc, spec.pilot_sc);

%% ===== 偵測硬體 =====================================================
try
    info = findsdru();
    fprintf('findsdru 偵測到 %d 台 USRP：\n', numel(info));
    for i = 1:numel(info)
        fprintf('  [%d] Platform=%s, Status=%s\n', ...
                i, info(i).Platform, info(i).Status);
    end
catch
    fprintf('findsdru 無法執行（不影響後續）。\n');
end

%% ===== 組裝完整 frame ===============================================
sts = gen_sts();
lts = gen_lts();

rng(spec.seed);                      % 固定種子，與 monitor 產生相同 payload
[ofdm_data, ~, ~, ~] = gen_ofdm_data(spec.num_ofdm, spec.qam_num);

pad = zeros(spec.pad_len, 1);
tx_frame = [pad; sts; lts; ofdm_data; pad];

% 正規化峰值，避免 USRP clipping
tx_frame = 0.7 * tx_frame / max(abs(tx_frame));

fprintf('Frame 組裝完成：總長 %d samples（STS=%d, LTS=%d, data=%d）\n', ...
        length(tx_frame), length(sts), length(lts), length(ofdm_data));

%% ===== 建立 USRP transmitter ========================================
% B210 可自訂 master clock，interpolation = masterClockRate / fs。
interp = cfg.masterClockRate / cfg.fs;
tx = comm.SDRuTransmitter( ...
    'Platform',            'B210', ...
    'SerialNum',           cfg.serialNum, ...
    'CenterFrequency',     cfg.fc, ...
    'Gain',                cfg.gain, ...
    'MasterClockRate',     cfg.masterClockRate, ...
    'InterpolationFactor', interp);
fprintf('USRP transmitter 已建立：B210, fc=%.3f MHz, fs=%.3f MHz\n', ...
        cfg.fc/1e6, cfg.fs/1e6);

%% ===== 即時 TX 圖（cfg.liveTxDisplay 控制）=========================
ts = []; sa = [];
if cfg.liveTxDisplay
    ts = timescope('SampleRate',cfg.fs, ...
        'TimeSpanSource','property','TimeSpan',length(tx_frame)/cfg.fs, ...
        'YLimits',[-1 1],'Title','USRP TX — Time Domain (正在發送完整 frame)', ...
        'ChannelNames',{'In-phase (I)','Quadrature (Q)'});
    sa = spectrumAnalyzer('SampleRate',cfg.fs, ...
        'ViewType','spectrum-and-spectrogram', ...
        'Title','USRP TX — Spectrum','ShowLegend',false);
end

%% ===== 釋放保護 =====================================================
cleanupObj = onCleanup(@() cleanupFcnTx(tx, ts, sa));

%% ===== 持續發射迴圈 =================================================
fprintf('\n開始持續發射完整 frame，持續 %d 秒。\n', cfg.runSeconds);
fprintf('（保持本視窗執行，另開視窗跑 usrp_ofdm_monitor.m）\n\n');

t0 = tic; iter = 0; underrunCnt = 0; consecErr = 0;
while toc(t0) < cfg.runSeconds
    iter = iter + 1;
    try
        underrun = tx(tx_frame);  consecErr = 0;
    catch ME
        consecErr = consecErr + 1;
        fprintf('[%6.1fs] tx 例外（連續第 %d 次）：%s\n', ...
                toc(t0), consecErr, ME.message);
        % 連續失敗時才嘗試 release 重啟一次，避免每次都重新初始化造成雪崩
        if consecErr == 5
            try, release(tx); catch, end
        end
        if consecErr >= 10
            error('連續 10 次發射失敗，請檢查 Ethernet 連線。最後錯誤：%s', ME.message);
        end
        pause(0.1);
        continue;
    end
    if underrun, underrunCnt = underrunCnt + 1; end

    if cfg.liveTxDisplay && mod(iter, cfg.displayEvery) == 0
        ts([real(tx_frame), imag(tx_frame)]);
        sa(tx_frame);
    end
    if mod(iter,200) == 0
        fprintf('[%6.1fs] 發射中... 已送 %d 個 frame，underrun %d 次\n', ...
                toc(t0), iter, underrunCnt);
    end
end
fprintf('\n發射結束。共送出 %d 個 frame，underrun %d 次。\n', iter, underrunCnt);

%% =====================================================================
%  區域函式（與 monitor 端相同的產生函式，務必保持一致）
%% =====================================================================
function sts = gen_sts()
    FFT_size = 64;
    short_sc = [-24 -20 -16 -12 -8 -4 4 8 12 16 20 24];
    sts_val = sqrt(13/6) * ...
        [1+1j,-1-1j,1+1j,-1-1j,-1-1j,1+1j,-1-1j,-1-1j,1+1j,1+1j,1+1j,1+1j];
    sts_f = zeros(FFT_size,1);
    sts_f(short_sc + FFT_size/2 + 1) = sts_val;
    sts_64 = ifft(ifftshift(sts_f), FFT_size);
    sts = repmat(sts_64(1:16), 10, 1);
end

function lts = gen_lts()
    FFT_size = 64;
    lts_sc = -26:26;
    lts_val = [1,1,-1,-1,1,1,-1,1,-1,1,1,1,1,1,1,-1,-1,1,1,-1,1,-1,1,1,1,1, ...
               0,1,-1,-1,1,1,-1,1,-1,1,-1,-1,-1,-1,-1,1,1,-1,-1,1,-1,1,-1,1,1,1,1];
    lts_f = zeros(FFT_size,1);
    lts_f(lts_sc + FFT_size/2 + 1) = lts_val;
    lts_64 = ifft(ifftshift(lts_f), FFT_size);
    lts = [lts_64(end-31:end); lts_64; lts_64];
end

function [x_cp, data_bits, data_sym, pilot_sym] = gen_ofdm_symbol(qam_num)
    FFT_size = 64; cp_size = 16;
    active_sc = [-26:-1 1:26];
    pilot_sc  = [-21 -7 7 21];
    data_sc   = setdiff(active_sc, pilot_sc);
    pilot_bits = randi([0 1], length(pilot_sc), 1);
    pilot_sym  = 2*pilot_bits - 1;
    data_bits  = randi([0 1], length(data_sc)*log2(qam_num), 1);
    data_sym   = qammod(data_bits, qam_num, 'InputType','bit','UnitAveragePower',true);
    Xc = zeros(FFT_size,1);
    sc2idx = @(k) k + FFT_size/2 + 1;
    Xc(sc2idx(pilot_sc)) = pilot_sym;
    Xc(sc2idx(data_sc))  = data_sym;
    a = ifft(ifftshift(Xc));
    x_cp = [a(end-cp_size+1:end); a];
end

function [ofdm_data, tx_bits, tx_data_syms, pilot_syms] = gen_ofdm_data(num_ofdm, qam_num)
    active_sc = [-26:-1 1:26]; pilot_sc = [-21 -7 7 21];
    data_sc = setdiff(active_sc, pilot_sc);
    FFT_size = 64; cp_size = 16;
    tx_bits      = zeros(log2(qam_num)*length(data_sc), num_ofdm);
    tx_data_syms = zeros(length(data_sc), num_ofdm);
    pilot_syms   = zeros(length(pilot_sc), num_ofdm);
    ofdm_data    = zeros((FFT_size+cp_size)*num_ofdm, 1);
    for s = 1:num_ofdm
        [x_cp, db, ds, ps] = gen_ofdm_symbol(qam_num);
        idx = (s-1)*(FFT_size+cp_size)+1 : s*(FFT_size+cp_size);
        ofdm_data(idx) = x_cp;
        tx_bits(:,s) = db; tx_data_syms(:,s) = ds; pilot_syms(:,s) = ps;
    end
end

function cleanupFcnTx(tx, ts, sa)
    fprintf('正在釋放 USRP transmitter 與顯示器...\n');
    try, release(tx); catch, end
    if ~isempty(ts), try, release(ts); catch, end, end
    if ~isempty(sa), try, release(sa); catch, end, end
    fprintf('已釋放。\n');
end
