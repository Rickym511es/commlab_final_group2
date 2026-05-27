%% =====================================================================
%  jam_experiment/jam_tx.m
%  B210 同時發射「真實 OFDM 訊號 (ch1)」+「干擾 jammer (ch2)」，
%  並依時間排程自動切換攻擊：
%
%      階段 0      ：NO ATTACK（baseline），30 秒
%      階段 1..7   ：attack_mode 1..7（TODO2..TODO8），各 30 秒
%
%  ch1 的 frame（pad/STS/LTS/data、seed）與 jam_experiment/jam_monitor.m
%  完全一致，monitor 才能偵測 / 解調 / 算 BER。
%  ch2 的 jammer 與 ch1 的 frame 逐 sample 對齊，攻擊落在正確的區段。
%
%  TX = B210（ChannelMapping [1 2]：ch1=真實 tx、ch2=jammer）
%  RX = N210（另開視窗跑 jam_monitor.m）
%
%  攻擊邏輯沿用 jammer1.m；本檔把它接上 USRP 並加上時間排程。
%  需要：Communications Toolbox / DSP System Toolbox / USRP Support Package
% =====================================================================

clear; clc; close all;

%% ===== 使用者參數 ===================================================
cfg.serialNum       = '34D9DC3';     % B210 (USRP-2901) 的 SerialNum
cfg.fc              = 885e6;
cfg.fs              = 1e6;
cfg.gain            = 15;            % 兩通道共用；太弱調高、爆掉調低
cfg.masterClockRate = 20e6;
cfg.secondsPerPhase = 20;            % 每個階段持續秒數
cfg.runBothTypes    = true;          % true: 每種攻擊兩型(noise+structured)各跑一段
cfg.jamType         = 2;             % runBothTypes=false 時才用：1=純雜訊, 2=結構化
cfg.liveTxDisplay   = true;
cfg.displayEvery    = 20;

%% ===== 干擾強度旋鈕（whole-frame RMS 相對於真實訊號 RMS 的倍數）====
% 用這兩個旋鈕掃不同 jammer 能量對連結的影響。
knob.noise_power     = 1;            % jam_type=1 用
knob.jam_power_scale = 1;            % jam_type=2 用
% jam_type=2 結構化模式的細部可調參數（對應 jammer1.m）
knob.sts_fake_shift  = 64;           % mode1: 假 STS 的 sample 偏移
knob.coarse_cfo_hz   = 80e3;         % mode2: 注在 STS 的假 CFO
knob.fine_cfo_hz     = 120e3;        % mode3: 注在 LTS 的假 CFO
knob.pilot_cfo_hz    = 60e3;         % mode4: 注在 data 的假 CFO
knob.flower_petals   = 6;            % mode7: flower 星座花瓣數

%% ===== Frame 規格（必須與 jam_monitor.m 完全一致）=================
spec.FFT_size  = 64;
spec.cp_size   = 16;
spec.qam_num   = 16;
spec.num_ofdm  = 20;
spec.pad_len   = 200;
spec.seed      = 12345;              % 固定種子：與 monitor 相同才能算 BER

%% ===== 組真實 frame（ch1）==========================================
sts = gen_sts();
lts = gen_lts();
rng(spec.seed);
[ofdm_data, ~, ~, ~] = gen_ofdm_data(spec.num_ofdm, spec.qam_num);
pad = zeros(spec.pad_len, 1);
real_frame = [pad; sts; lts; ofdm_data; pad];
real_frame = 0.7 * real_frame / max(abs(real_frame));   % 峰值正規化，避免 clipping
tx_rms = rms(real_frame);

info = frame_info(spec, length(sts), length(lts));
fprintf('真實 frame 組裝完成：長度 %d samples（與 monitor 一致）\n', length(real_frame));

%% ===== 偵測硬體 =====================================================
try
    sdrinfo = findsdru();
    fprintf('findsdru 偵測到 %d 台 USRP。\n', numel(sdrinfo));
catch
    fprintf('findsdru 無法執行（不影響後續，會用 SerialNum 直接連）。\n');
end

%% ===== 排程 =========================================================
sched = make_schedule(cfg);
numPhases = numel(sched);
totalSec  = numPhases * cfg.secondsPerPhase;
fprintf('\n排程共 %d 個階段，每階段 %d 秒，總長 %d 秒：\n', ...
        numPhases, cfg.secondsPerPhase, totalSec);
for i = 1:numPhases
    fprintf('  [%2d] %3d-%3ds : %s\n', i, ...
            (i-1)*cfg.secondsPerPhase, i*cfg.secondsPerPhase, sched(i).label);
end

%% ===== 建立 USRP transmitter（雙通道）==============================
interp = cfg.masterClockRate / cfg.fs;
tx = comm.SDRuTransmitter( ...
    'Platform',            'B210', ...
    'SerialNum',           cfg.serialNum, ...
    'CenterFrequency',     cfg.fc, ...
    'Gain',                cfg.gain, ...
    'MasterClockRate',     cfg.masterClockRate, ...
    'InterpolationFactor', interp, ...
    'ChannelMapping',      [1 2]);
fprintf('\nB210 transmitter 已建立：fc=%.3f MHz, fs=%.3f MHz\n', ...
        cfg.fc/1e6, cfg.fs/1e6);

%% ===== 即時 TX 圖 ===================================================
ts = []; cd_jam = [];
if cfg.liveTxDisplay
    ts = timescope('SampleRate', cfg.fs, ...
        'TimeSpanSource','property','TimeSpan', length(real_frame)/cfg.fs, ...
        'Title','TX Time Domain：ch1 真實訊號 / ch2 jammer', ...
        'ChannelNames',{'ch1 real (Re)','ch2 jammer (Re)'}, ...
        'AxesScaling','Auto');
    % jammer 乾淨星座：直接畫 ch2 在 data 子載波上的符號。
    % TODO8（高功率資料覆蓋）時這裡會是清楚的 flower；其餘攻擊多半空白或只有少數點。
    cd_jam = comm.ConstellationDiagram( ...
        'Title','TX Jammer Constellation（TODO8 應為 flower）', ...
        'ShowReferenceConstellation',false, ...
        'XLimits',[-2 2],'YLimits',[-2 2]);
end

%% ===== 釋放保護 =====================================================
cleanupObj = onCleanup(@() cleanupFcnTx(tx, ts, cd_jam));

%% ===== 主迴圈 =======================================================
fprintf('\n開始發射，總長 %d 秒。（另開視窗跑 jam_monitor.m）\n\n', totalSec);
t0 = tic; iter = 0; curPhase = 0; consecErr = 0; underrunCnt = 0;
txMat = [real_frame, zeros(size(real_frame))];   % 安全初值

while toc(t0) < totalSec
    elapsed = toc(t0);

    % --- 階段切換：重建 jammer 與雙通道矩陣 ---
    p = min(numPhases, floor(elapsed / cfg.secondsPerPhase) + 1);
    if p ~= curPhase
        curPhase = p;
        s = sched(p);
        jammer = build_jammer(s.mode, s.type, real_frame, info, cfg.fs, knob);
        % 兩條 DAC 各自獨立 clip：真實通道固定不動，只在 jammer 峰值超過上限時縮 jammer。
        jpk = max(abs(jammer));
        if jpk > 0.95
            jammer = jammer * (0.95 / jpk);
            fprintf('  (jammer 峰值 %.2f > 0.95，縮放保護)\n', jpk);
        end
        txMat = [real_frame, jammer];
        fprintf('[%6.1fs] >>> 階段 %d/%d：%s | jam_rms/tx_rms=%.2f\n', ...
                elapsed, p, numPhases, s.label, rms(jammer)/max(tx_rms,1e-12));
        if cfg.liveTxDisplay
            ts([real(txMat(:,1)), real(txMat(:,2))]);
            feed_jam_const(cd_jam, jammer, info);
        end
    end

    % --- 發射 ---
    iter = iter + 1;
    try
        underrun = tx(txMat);  consecErr = 0;
    catch ME
        consecErr = consecErr + 1;
        fprintf('[%6.1fs] tx 例外（連續第 %d 次）：%s\n', ...
                toc(t0), consecErr, ME.message);
        if consecErr == 5, try, release(tx); catch, end, end
        if consecErr >= 10
            error('連續 10 次發射失敗，請檢查 USB/連線。最後錯誤：%s', ME.message);
        end
        pause(0.1);
        continue;
    end
    if underrun, underrunCnt = underrunCnt + 1; end

    if cfg.liveTxDisplay && mod(iter, cfg.displayEvery) == 0
        ts([real(txMat(:,1)), real(txMat(:,2))]);
        feed_jam_const(cd_jam, txMat(:,2), info);
    end
end
fprintf('\n發射結束。共送出 %d 個 frame，underrun %d 次。\n', iter, underrunCnt);

%% =====================================================================
%  區域函式
%% =====================================================================
function info = frame_info(spec, sts_len, lts_len)
% 依 frame 規格算出各區段在 frame 內的 index（給 jammer 對齊用）。
    pad = spec.pad_len;  FFT_size = spec.FFT_size;  cp = spec.cp_size;
    ns  = spec.num_ofdm; sym = FFT_size + cp;
    info.FFT_size         = FFT_size;
    info.cp_size          = cp;
    info.sym_len          = sym;
    info.num_ofdm_symbols = ns;
    info.qam_num          = spec.qam_num;
    info.sts_start        = pad + 1;
    info.sts_end          = info.sts_start + sts_len - 1;
    info.lts_start        = info.sts_end + 1;
    info.lts_end          = info.lts_start + lts_len - 1;
    info.lts_body_start   = info.lts_start + 32;
    info.data_start       = info.lts_end + 1;
    info.data_end         = info.data_start + ns*sym - 1;
    info.cp_starts        = info.data_start + (0:ns-1)*sym;
end

function sched = make_schedule(cfg)
% 階段排程：第 1 段不攻擊；之後對每個 attack_mode 1..7 依序排入要跑的 jam_type。
% runBothTypes=true -> 每個 mode 先 type1(noise) 再 type2(structured)，共 15 段。
% runBothTypes=false-> 每個 mode 只跑 cfg.jamType，共 8 段。
    labels = { ...
        'TODO2  STS 時間同步攻擊'; ...
        'TODO3  STS 粗 CFO 攻擊'; ...
        'TODO4  LTS 細 CFO 攻擊'; ...
        'TODO5  pilot CFO 攻擊'; ...
        'TODO6  LTS 通道估計攻擊'; ...
        'TODO7  CP 循環卷積攻擊'; ...
        'TODO8  高功率資料覆蓋 (flower)'};
    typeName = {'noise', 'structured'};
    if cfg.runBothTypes, types = [1 2]; else, types = cfg.jamType; end
    sched = struct('mode', 0, 'type', 0, 'label', 'NO ATTACK (baseline)');
    for m = 1:7
        for t = types
            sched(end+1) = struct('mode', m, 'type', t, ...
                'label', sprintf('%s（type=%d %s）', labels{m}, t, typeName{t})); %#ok<AGROW>
        end
    end
end

function jammer = build_jammer(attack_mode, jam_type, tx_signal, info, fs, knob)
% 依攻擊模式產生與 tx_signal 等長、逐 sample 對齊的 jammer。
% 干擾功率以 victim RMS 的倍數設定（knob.noise_power / jam_power_scale），
% 方便掃不同 jammer 能量對連結的影響。attack_mode = 0 -> baseline，回傳全零。
% 攻擊邏輯與 jammer1.m 一致。
    N = length(tx_signal);
    jammer = zeros(N, 1);
    if attack_mode == 0, return; end

    tx_rms = rms(tx_signal);
    noise  = @(n) (randn(n,1) + 1j*randn(n,1)) / sqrt(2);

    noise_power     = knob.noise_power;
    jam_power_scale = knob.jam_power_scale;
    sts_fake_shift  = knob.sts_fake_shift;
    coarse_cfo_hz   = knob.coarse_cfo_hz;
    fine_cfo_hz     = knob.fine_cfo_hz;
    pilot_cfo_hz    = knob.pilot_cfo_hz;
    flower_petals   = knob.flower_petals;

    % (1) TODO2 : 攻擊 STS（時間同步）
    if attack_mode == 1
        if jam_type == 1
            idx = info.sts_start : info.sts_end;
            jammer(idx) = noise_power * tx_rms * noise(numel(idx));
        else
            sts = gen_sts(); sts = sts / rms(sts);
            fake_pos = info.sts_start + sts_fake_shift;
            fake_end = fake_pos + length(sts) - 1;
            if fake_pos >= 1 && fake_end <= N
                idx = fake_pos:fake_end;
                jammer(idx) = jam_power_scale * tx_rms * sts;
            end
        end
    end

    % (2) TODO3 : 攻擊 STS（粗 CFO）
    if attack_mode == 2
        idx = info.sts_start : info.sts_end;
        if jam_type == 1
            jammer(idx) = noise_power * tx_rms * noise(numel(idx));
        else
            sts = gen_sts(); sts = sts / rms(sts);
            n_sts = (0:length(sts)-1).';
            sts_attack = sts .* exp(1j*2*pi*coarse_cfo_hz*n_sts/fs);
            jammer(idx) = jam_power_scale * tx_rms * sts_attack;
        end
    end

    % (3) TODO4 : 攻擊 LTS（細 CFO）
    if attack_mode == 3
        idx = info.lts_start : info.lts_end;
        if jam_type == 1
            jammer(idx) = noise_power * tx_rms * noise(numel(idx));
        else
            lts = gen_lts(); lts = lts / rms(lts);
            n_lts = (0:length(lts)-1).';
            lts_attack = lts .* exp(1j*2*pi*fine_cfo_hz*n_lts/fs);
            jammer(idx) = jam_power_scale * tx_rms * lts_attack;
        end
    end

    % (4) TODO5 : 攻擊 pilot（CFO）—— 只點亮 4 個 pilot 子載波
    if attack_mode == 4
        idx = info.data_start : info.data_end;
        FFT_size  = info.FFT_size; cp_size = info.cp_size; sym_len = info.sym_len;
        sc2idx    = @(k) k + FFT_size/2 + 1;
        pilot_idx = sc2idx([-21 -7 7 21]);
        nsyms     = info.num_ofdm_symbols;

        fake_data = zeros(nsyms * sym_len, 1);
        for k = 1:nsyms
            X = zeros(FFT_size, 1);
            if jam_type == 1
                X(pilot_idx) = noise(length(pilot_idx));
            else
                X(pilot_idx) = exp(1j*2*pi*rand(length(pilot_idx),1));
            end
            x_time = ifft(ifftshift(X), FFT_size);
            x_cp   = [x_time(end-cp_size+1:end); x_time];
            s = (k-1)*sym_len + 1;
            fake_data(s : s+sym_len-1) = x_cp;
        end
        fake_data = fake_data / rms(fake_data);
        if jam_type == 2
            n_data    = (0:length(fake_data)-1).';
            fake_data = fake_data .* exp(1j*2*pi*pilot_cfo_hz*n_data/fs);
            jammer(idx) = jam_power_scale * tx_rms * fake_data;
        else
            jammer(idx) = noise_power * tx_rms * fake_data;
        end
    end

    % (5) TODO6 : 攻擊 LTS（通道估計）
    if attack_mode == 5
        idx = info.lts_start : info.lts_end;
        if jam_type == 1
            jammer(idx) = noise_power * tx_rms * noise(numel(idx));
        else
            FFT_size = info.FFT_size;
            lts_sc = -26:26;
            lts_val = [1, 1,-1,-1, 1, 1,-1, 1,-1, 1, 1, 1, 1, 1, 1, ...
                      -1,-1, 1, 1,-1, 1,-1, 1, 1, 1, 1, 0, 1,-1,-1, ...
                       1, 1,-1, 1,-1, 1,-1,-1,-1,-1,-1, 1, 1,-1,-1, ...
                       1,-1, 1,-1, 1, 1, 1, 1];
            mask = ones(size(lts_val)); mask(1:2:end) = -1;
            lts_f = zeros(FFT_size, 1);
            lts_f(lts_sc + FFT_size/2 + 1) = lts_val .* mask;
            lts_body = ifft(ifftshift(lts_f), FFT_size);
            lts_fake = [lts_body(end-31:end); lts_body; lts_body];
            lts_fake = lts_fake / rms(lts_fake);
            jammer(idx) = jam_power_scale * tx_rms * lts_fake;
        end
    end

    % (6) TODO7 : 攻擊 CP（循環卷積）
    if attack_mode == 6
        if jam_type == 1
            for s = info.cp_starts(:).'
                idx = s : s + info.cp_size - 1;
                jammer(idx) = noise_power * tx_rms * noise(info.cp_size);
            end
        else
            [fake_ofdm, ~, ~, ~] = gen_ofdm_data(info.num_ofdm_symbols, info.qam_num);
            fake_ofdm = fake_ofdm / rms(fake_ofdm);
            for k = 0:info.num_ofdm_symbols-1
                s          = info.cp_starts(k+1);
                body_start = k * info.sym_len + info.cp_size + 1;
                wrong_cp   = fake_ofdm(body_start : body_start + info.cp_size - 1);
                idx = s : s + info.cp_size - 1;
                jammer(idx) = jam_power_scale * tx_rms * wrong_cp;
            end
        end
    end

    % (7) TODO8 : 高功率 OFDM 資料覆蓋（flower 星座）
    if attack_mode == 7
        idx = info.data_start : info.data_end;
        if jam_type == 1
            jammer(idx) = noise_power * tx_rms * noise(numel(idx));
        else
            FFT_size  = info.FFT_size; cp_size = info.cp_size; sym_len = info.sym_len;
            active_sc = [-26:-1 1:26];
            sc2idx    = @(k) k + FFT_size/2 + 1;
            active_idx= sc2idx(active_sc);
            nsyms     = info.num_ofdm_symbols; num_act = length(active_sc);

            fake_data = zeros(nsyms * sym_len, 1);
            for n = 1:nsyms
                theta   = 2*pi*rand(num_act, 1);
                r       = abs(cos(flower_petals * theta / 2));
                symbols = r .* exp(1j*theta);
                X = zeros(FFT_size, 1);
                X(active_idx) = symbols;
                x_time = ifft(ifftshift(X), FFT_size);
                x_cp   = [x_time(end-cp_size+1:end); x_time];
                s = (n-1)*sym_len + 1;
                fake_data(s : s+sym_len-1) = x_cp;
            end
            fake_data = fake_data / rms(fake_data);
            jammer(idx) = jam_power_scale * tx_rms * fake_data;
        end
    end

    % whole-frame RMS 正規化：讓 rms(jammer)/rms(tx_signal) == 旋鈕值
    if jam_type == 1, active_knob = noise_power; else, active_knob = jam_power_scale; end
    jr = rms(jammer);
    if jr > 1e-12 && active_knob > 0
        jammer = jammer * (active_knob * tx_rms / jr);
    end
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

function feed_jam_const(cd_jam, jammer, info)
% 從 jammer 時域抽出 data 子載波的頻域符號，餵給星座圖（看 flower 用）。
% jammer 在 data 區若沒能量（如 STS/LTS 攻擊）就不更新。
    if isempty(cd_jam), return; end
    FFT_size = info.FFT_size; cp_size = info.cp_size;
    sym_len  = info.sym_len;  ns = info.num_ofdm_symbols;
    data_sc  = setdiff([-26:-1 1:26], [-21 -7 7 21]);
    didx     = data_sc + FFT_size/2 + 1;
    S = zeros(numel(didx), ns);
    for k = 0:ns-1
        b = info.data_start + k*sym_len + cp_size;
        if b+FFT_size-1 > length(jammer), break; end
        X = fftshift(fft(jammer(b:b+FFT_size-1), FFT_size));
        S(:, k+1) = X(didx);
    end
    p = rms(S(:));
    if p > 1e-9, cd_jam(S(:) / p); end   % 有能量才畫，並正規化到合理大小
end

function cleanupFcnTx(tx, ts, cd_jam)
    fprintf('正在釋放 USRP transmitter 與顯示器...\n');
    try, release(tx); catch, end
    if ~isempty(ts),     try, release(ts);     catch, end, end
    if ~isempty(cd_jam), try, release(cd_jam); catch, end, end
    fprintf('已釋放。\n');
end
