%% =====================================================================
%  usrp_ofdm_monitor.m
%  OFDM 即時接收監看 + 鏈路品質儀表（整合 Lab 5 接收鏈）
%
%  功能：
%    1. spectrumAnalyzer    -> 即時頻譜（看得到 jammer 的能量）
%    2. ConstellationDiagram-> 即時星座圖（被攻擊時會散開）
%    3. 鏈路儀表            -> frame 偵測率、BER、SNR、throughput
%    4. 干擾偵測            -> SNR / 偵測率掉太多時跳出 JAMMING DETECTED
%
%  接收流程（每個 capture）：
%    STS matched filter 找 frame 起點 -> CFO 校正 -> LTS 估通道
%    -> equalize -> pilot 校正 -> 解調 -> 比對 BER / 算 SNR
%
%  搭配：usrp_ofdm_tx.m（必須用「相同」的 frame 參數與 seed）
%  RX = N200 (USRP-2920)；TX = B210 (USRP-2901)。
%  兩支在不同 MATLAB 視窗各跑一份。
%
%  需要：Communications Toolbox / DSP System Toolbox / USRP Support Package
% =====================================================================

clear; clc; close all;

%% ===== 使用者參數 ===================================================
cfg.platform        = 'N200/N210/USRP2';
cfg.ipAddress       = '192.168.10.2'; % N200 (USRP-2920) 的 IP
cfg.fc              = 885e6;
cfg.fs              = 1e6;
cfg.gain            = 20;
cfg.samplesPerFrame = 8192;          % 要夠大，能包住至少一個完整 frame
cfg.runSeconds      = 300;
cfg.displayEvery    = 5;             % 星座/頻譜每幾個 capture 更新一次
cfg.detectRatio     = 8;             % STS 相關峰 / 雜訊中位數，超過才算偵測到
cfg.calibSeconds    = 6;             % 開頭幾秒當基準校正期
cfg.snrDropDb       = 6;             % SNR 比基準掉超過這麼多 dB -> 判定被干擾
cfg.detRateJam      = 0.5;           % 近期偵測率低於此 -> 判定被干擾

%% ===== Frame 規格（必須與 usrp_ofdm_tx.m 完全一致）=================
spec.FFT_size  = 64;
spec.cp_size   = 16;
spec.active_sc = [-26:-1, 1:26];
spec.pilot_sc  = [-21 -7 7 21];
spec.qam_num   = 16;
spec.num_ofdm  = 20;
spec.pad_len   = 200;
spec.seed      = 12345;              % 固定種子：TX/RX 靠它產生相同 payload
spec.data_sc   = setdiff(spec.active_sc, spec.pilot_sc);

%% ===== 重建參考訊號（與 TX 端產生的內容相同）======================
sts = gen_sts();   sts = sts / rms(sts);
lts = gen_lts();   lts = lts / rms(lts);
rng(spec.seed);    % 固定種子，確保與 TX 產生相同 payload
[ofdm_data, tx_bits, tx_data_syms, pilot_syms] = ...
    gen_ofdm_data(spec.num_ofdm, spec.qam_num);

frame_len   = 2*spec.pad_len + length(sts) + length(lts) + length(ofdm_data);
lts_f_known = fftshift(fft(lts(33:96)));        % 已知 LTS 的頻域樣式
bits_per_frame = spec.num_ofdm * length(spec.data_sc) * log2(spec.qam_num);

fprintf('Frame 長度 = %d samples，每 frame 資料量 = %d bits\n', ...
        frame_len, bits_per_frame);

%% ===== 建立 USRP receiver（連續串流模式）==========================
% N200 master clock 固定 100 MHz，decimation = 100e6 / fs。
% 監看迴圈要長時間連續收，故用連續串流（不開 burst mode）。
deci = 100e6 / cfg.fs;
rx = comm.SDRuReceiver( ...
    'Platform',         'N200/N210/USRP2', ...
    'IPAddress',        cfg.ipAddress, ...
    'CenterFrequency',  cfg.fc, ...
    'Gain',             cfg.gain, ...
    'SamplesPerFrame',  cfg.samplesPerFrame, ...
    'DecimationFactor', deci, ...
    'OutputDataType',   'double');
fprintf('USRP receiver 已建立：N200, fc=%.3f MHz, fs=%.3f MHz\n', ...
        cfg.fc/1e6, cfg.fs/1e6);

%% ===== 顯示器：頻譜 + 星座 + 儀表 ==================================
sa = spectrumAnalyzer('SampleRate', cfg.fs, ...
    'ViewType','spectrum-and-spectrogram', ...
    'Title','RX Spectrum（jammer 能量會出現在這）','ShowLegend',false);

% RX 時域圖（對應 TX 的 timescope）。振幅隨 gain/距離變動，故自動縮放。
ts_rx = timescope('SampleRate', cfg.fs, ...
    'TimeSpanSource','property','TimeSpan', cfg.samplesPerFrame/cfg.fs, ...
    'Title','RX Time Domain（接收訊號 I/Q；被干擾時振幅會暴衝）', ...
    'ChannelNames',{'In-phase (I)','Quadrature (Q)'}, ...
    'AxesScaling','Auto');

ref_const = qammod(0:spec.qam_num-1, spec.qam_num, 'UnitAveragePower', true);
cd_rx = comm.ConstellationDiagram( ...
    'Title','RX Equalized Constellation（被攻擊時會散開）', ...
    'ShowReferenceConstellation',true, ...
    'ReferenceConstellation',ref_const, ...
    'XLimits',[-2 2],'YLimits',[-2 2]);

dash = makeDashboard();

%% ===== 釋放保護 =====================================================
cleanupObj = onCleanup(@() cleanupFcn(rx, sa, cd_rx, ts_rx));

%% ===== 暖機 =========================================================
fprintf('暖機中...\n');
for k = 1:5, try, rx(); catch, end, end

%% ===== 主迴圈 =======================================================
fprintf('\n開始監看 %d 秒。前 %d 秒為基準校正期。\n\n', ...
        cfg.runSeconds, cfg.calibSeconds);

t0 = tic; iter = 0; consecErr = 0;
framesDetected = 0; goodBits = 0;
calibSNR = []; baselineSNR = NaN;
WIN = 40;                            % 近期統計視窗大小
recentDet = false(1,WIN); recentSNR = nan(1,WIN); recentBER = nan(1,WIN);
ridx = 0;

while toc(t0) < cfg.runSeconds
    iter = iter + 1;

    % --- 擷取 ---
    try
        [data,len,ovf] = rx();  consecErr = 0;
    catch ME
        consecErr = consecErr + 1;
        % 連續失敗時才嘗試 release 重啟一次，避免每次都重新初始化造成雪崩
        if consecErr == 5
            try, release(rx); catch, end
        end
        if consecErr >= 10
            error('連續接收失敗，請檢查連線。最後錯誤：%s', ME.message);
        end
        pause(0.1);
        continue;
    end
    if len == 0, continue; end   % overflow(ovf) 時當前 buffer 仍有效，照常處理

    % --- 接收處理：偵測 + 解調 ---
    res = processCapture(data, sts, lts, frame_len, spec, ...
                         cfg.fs, tx_bits, tx_data_syms, pilot_syms, ...
                         lts_f_known, cfg.detectRatio);

    % --- 更新近期統計視窗 ---
    ridx = mod(ridx, WIN) + 1;
    recentDet(ridx) = res.detected;
    if res.detected
        recentSNR(ridx) = res.snr_dB;  recentBER(ridx) = res.ber;
        framesDetected = framesDetected + 1;
        goodBits = goodBits + bits_per_frame * max(0, 1 - res.ber);
    else
        recentSNR(ridx) = NaN;  recentBER(ridx) = NaN;
    end

    % --- 基準校正：開頭幾秒收集乾淨環境的 SNR ---
    elapsed = toc(t0);
    if elapsed < cfg.calibSeconds
        if res.detected, calibSNR(end+1) = res.snr_dB; end %#ok<SAGROW>
    elseif isnan(baselineSNR)
        if ~isempty(calibSNR)
            baselineSNR = median(calibSNR);
            fprintf('基準 SNR 校正完成：%.1f dB\n', baselineSNR);
        else
            baselineSNR = 0;   % 校正期沒收到 frame，給保守值
            fprintf('警告：校正期未偵測到 frame，基準 SNR 設為 0。\n');
        end
    end

    % --- 即時顯示（節流）---
    if mod(iter, cfg.displayEvery) == 0
        sa(data);
        ts_rx([real(data(:)), imag(data(:))]);
        if res.detected, cd_rx(res.eq_data_syms(:)); end

        detRate   = mean(recentDet);
        recSNR    = mean(recentSNR, 'omitnan');
        recBER    = mean(recentBER, 'omitnan');
        tputKbps  = goodBits / max(elapsed,1e-3) / 1e3;

        % --- 干擾判定 ---
        if elapsed < cfg.calibSeconds || isnan(baselineSNR)
            statusTxt = 'CALIBRATING...'; statusCol = [0.85 0.65 0.1];
        else
            jammed = false;
            if ~isnan(recSNR) && recSNR < baselineSNR - cfg.snrDropDb
                jammed = true;
            end
            if detRate < cfg.detRateJam
                jammed = true;
            end
            if jammed
                statusTxt = 'JAMMING DETECTED'; statusCol = [0.85 0.15 0.15];
            else
                statusTxt = 'LINK OK';          statusCol = [0.15 0.65 0.2];
            end
        end

        updateDashboard(dash, statusTxt, statusCol, framesDetected, ...
            detRate, recBER, recSNR, baselineSNR, tputKbps);
    end
end

fprintf('\n監看結束。共偵測到 %d 個 frame。\n', framesDetected);

%% =====================================================================
%  區域函式
%% =====================================================================
function res = processCapture(data, sts, lts, frame_len, spec, ...
                    fs, tx_bits, tx_data_syms, pilot_syms, lts_f_known, detectRatio)
% 對一個 capture 做 STS 偵測 + Lab 5 接收鏈解調。
    res.detected = false;  res.eq_data_syms = []; res.ber = NaN; res.snr_dB = NaN;

    data = data(:);
    FFT_size = spec.FFT_size;  cp_size = spec.cp_size;  pad_len = spec.pad_len;
    qam_num  = spec.qam_num;

    % --- STS matched filter 偵測 ---
    mf   = conj(flipud(sts(:)));
    corr = abs(conv(data, mf));
    [pk, peak_idx] = max(corr);
    noiseLvl = median(corr) + 1e-12;
    res.ratio = pk / noiseLvl;
    if res.ratio < detectRatio, return; end          % 峰不夠突出 -> 沒偵測到

    sts_start   = peak_idx - length(sts) + 1;
    frame_start = sts_start - pad_len;
    frame_end   = frame_start + frame_len - 1;
    if frame_start < 1 || frame_end > length(data), return; end  % frame 不完整

    rx_frame = data(frame_start:frame_end);
    rx_frame = rx_frame - mean(rx_frame);            % 去 DC offset

    % --- CFO 估計（STS 16-sample 週期）+ 校正 ---
    D = 16;
    rx_sts = rx_frame(pad_len+1 : pad_len+length(sts));
    P = sum(conj(rx_sts(1:end-D)) .* rx_sts(1+D:end));
    cfo = angle(P) * fs / (2*pi*D);
    n = (0:length(rx_frame)-1).';
    rx_cfo = rx_frame .* exp(-1j*2*pi*cfo*n/fs);

    % --- LTS 估通道 ---
    first_lts = pad_len + length(sts) + 33;
    H1 = estimateChannelFromLTS(rx_cfo(first_lts:first_lts+FFT_size-1), lts_f_known);
    H2 = estimateChannelFromLTS(rx_cfo(first_lts+FFT_size:first_lts+2*FFT_size-1), lts_f_known);
    H  = (H1 + H2) / 2;

    % --- 解調 ---
    sc2idx   = @(k) k + FFT_size/2 + 1;
    data_idx = sc2idx(spec.data_sc);
    pilot_idx= sc2idx(spec.pilot_sc);
    data_start = pad_len + length(sts) + length(lts) + 1;
    sym_len = FFT_size + cp_size;

    num_ofdm = spec.num_ofdm;
    eq_data = zeros(length(spec.data_sc), num_ofdm);
    for k = 1:num_ofdm
        seg = rx_cfo(data_start+(k-1)*sym_len : data_start+k*sym_len-1);
        Y = ofdmDemodSymbol(seg, FFT_size, cp_size);
        X = equalizeSymbol(Y, H);
        % pilot 殘餘相位校正
        theta = angle(sum(X(pilot_idx) .* conj(pilot_syms(:,k))));
        X = X * exp(-1j*theta);
        d = X(data_idx);
        d(~isfinite(d)) = 0;
        p = mean(abs(d).^2);
        if isfinite(p) && p > 1e-12, d = d / sqrt(p); else, d = zeros(size(d)); end
        eq_data(:,k) = d(:);
    end

    % --- BER ---
    rx_bits = zeros(size(tx_bits));
    for k = 1:num_ofdm
        s = eq_data(:,k); s(~isfinite(s)) = 0;
        rx_bits(:,k) = qamdemod(s, qam_num, 'OutputType','bit','UnitAveragePower',true);
    end
    res.ber = sum(rx_bits(:) ~= tx_bits(:)) / numel(tx_bits);

    % --- SNR（EVM-like）---
    rxv = eq_data(:);  txv = tx_data_syms(:);
    m = min(numel(rxv),numel(txv));
    err = rxv(1:m) - txv(1:m);
    res.snr_dB = 10*log10(mean(abs(txv(1:m)).^2) / (mean(abs(err).^2)+1e-12));

    res.detected = true;
    res.eq_data_syms = eq_data;
end

function H = estimateChannelFromLTS(rx_lts, lts_f_known)
    rx_lts_f = fftshift(fft(rx_lts));
    H = zeros(size(rx_lts_f));
    v = abs(lts_f_known) > 1e-12;
    H(v) = rx_lts_f(v) ./ lts_f_known(v);
end

function Y = ofdmDemodSymbol(seg, FFT_size, cp_size)
    Y = fftshift(fft(seg(cp_size+1:end), FFT_size));
end

function x = equalizeSymbol(Y, H)
    x = zeros(size(Y));
    Y(~isfinite(Y)) = 0;  H(~isfinite(H)) = 0;
    v = abs(H) > 1e-6;
    x(v) = Y(v) ./ H(v);
    x(~isfinite(x)) = 0;
end

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

function dash = makeDashboard()
    f = figure('Name','OFDM Link Monitor','Color','w','Position',[100 100 460 420]);
    ax = axes('Parent',f,'Position',[0 0 1 1]); axis(ax,[0 1 0 1]); axis(ax,'off');
    dash.statusBox = rectangle('Parent',ax,'Position',[0.06 0.78 0.88 0.15], ...
        'FaceColor',[0.85 0.65 0.1],'EdgeColor','none');
    dash.status = text(ax,0.5,0.855,'CALIBRATING...','FontSize',20, ...
        'FontWeight','bold','Color','w','HorizontalAlignment','center');
    labels = {'Frames detected','Detection rate','BER (recent)', ...
              'SNR (recent)','Baseline SNR','Throughput'};
    dash.val = gobjects(1,6);
    for i = 1:6
        y = 0.66 - (i-1)*0.105;
        text(ax,0.10,y,labels{i},'FontSize',13,'Color',[0.3 0.3 0.3]);
        dash.val(i) = text(ax,0.92,y,'--','FontSize',14,'FontWeight','bold', ...
            'HorizontalAlignment','right','Color','k');
    end
    drawnow;
end

function updateDashboard(dash, statusTxt, statusCol, frames, detRate, ber, snr, baseSNR, tput)
    dash.statusBox.FaceColor = statusCol;
    dash.status.String = statusTxt;
    dash.val(1).String = sprintf('%d', frames);
    dash.val(2).String = sprintf('%.0f %%', 100*detRate);
    if isnan(ber),  dash.val(3).String = '--';
    else,           dash.val(3).String = sprintf('%.2e', ber); end
    if isnan(snr),  dash.val(4).String = '--';
    else,           dash.val(4).String = sprintf('%.1f dB', snr); end
    if isnan(baseSNR), dash.val(5).String = '--';
    else,              dash.val(5).String = sprintf('%.1f dB', baseSNR); end
    dash.val(6).String = sprintf('%.1f kbps', tput);
    drawnow limitrate;
end

function cleanupFcn(rx, sa, cd_rx, ts_rx)
    fprintf('正在釋放 USRP 與顯示器...\n');
    try, release(rx);    catch, end
    try, release(sa);    catch, end
    try, release(cd_rx); catch, end
    try, release(ts_rx); catch, end
    fprintf('已釋放。\n');
end
