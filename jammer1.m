%(0)
info = findsdru();
disp(info);

%(1) USRP-TX object(real tarnsmitter + jammer)
%%% TX parameters %%%
tx_serial_num = '34D9DC3';
fc = 855e6;
fs = 10e6;
inte_factor = 20e6/fs;
tx_gain = 20;
%%% GONMAN %%%
tx_usrp = comm.SDRuTransmitter( ...
        'Platform',            'B210', ...
        'SerialNum',           tx_serial_num, ...
        'CenterFrequency',     fc, ...
        'Gain',                tx_gain, ...
        'MasterClockRate',     20e6, ...
        'InterpolationFactor', inte_factor, ...
        'ChannelMapping',      [1 2]);

%%% real-transmitter signal %%%
% assume channel 1 for real-transmitter
% TODO1 : 802.11a/g-like signal
num_ofdm_symbols = 10;
qam_num          = 16;
[tx_signal, info] = gen_80211ag_frame(num_ofdm_symbols, qam_num);
%%% GONMAN %%%

%%% jammer signal %%%
% assume channel 2 for jammer
%%% pick attack mode, jam type, and the matching power knob %%%
attack_mode      = 4;       % 1=TODO2 ... 7=TODO8
jam_type         = 1;       % 1 = pure noise jam,  2 = structured fake-signal jam

% independent power knobs (each only matters for its own jam_type)
noise_power      = 1;       % noise-mode amplitude  (RMS multiple of tx_signal RMS)
jam_power_scale  = 1;       % structured-mode amplitude (RMS multiple of tx_signal RMS)

% per-attack tunables for the STRUCTURED mode only (jam_type = 2)
sts_fake_shift   = 64;      % TODO2: sample offset of the fake STS
coarse_cfo_hz    = 80e3;    % TODO3: fake carrier offset injected on STS  (Hz)
fine_cfo_hz      = 120e3;   % TODO4: fake carrier offset injected on LTS  (Hz)
pilot_cfo_hz     = 60e3;    % TODO5: fake carrier offset across the data  (Hz)
flower_petals    = 6;       % TODO8: number of petals in the flower constellation
%%% GONMAN %%%

jammer = zeros(length(tx_signal), 1);
N      = length(tx_signal);
tx_rms = rms(tx_signal);
noise  = @(n) (randn(n,1) + 1j*randn(n,1)) / sqrt(2);

%(1) TODO2 : attack sts for timing synchronization
% Receiver runs conv(rx, conj(flipud(sts))) and locks onto the largest peak.
%   jam_type=1 : flood the STS region with noise so the matched filter has
%                no clean peak to find.
%   jam_type=2 : place a FAKE STS shifted by sts_fake_shift samples; the
%                matched filter peaks on OUR copy and frame_start is wrong.
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

%(2) TODO3 : attack sts for coarse CFO
% Coarse CFO uses the 16-sample periodicity inside the STS.
%   jam_type=1 : noise on the STS region randomizes the inter-symbol phase.
%   jam_type=2 : send an STS modulated by exp(j*2*pi*coarse_cfo_hz*n/fs) so
%                the receiver folds the fake offset into its CFO estimate.
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

%(3) TODO4 : attack lts for fine CFO
% Fine CFO uses angle(sum(conj(lts1).*lts2)) on the two 64-sample LTS halves.
%   jam_type=1 : noise on LTS destroys the phase relationship between halves.
%   jam_type=2 : send an LTS modulated by exp(j*2*pi*fine_cfo_hz*n/fs).
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

%(4) TODO5 : attack pilot for CFO
% Per-symbol pilot phase tracking uses pilots at [-21 -7 7 21]. BOTH modes
% energize ONLY the 4 pilot subcarriers in frequency domain; the 48 data
% subcarriers stay at zero. (Note: the time-domain trace still looks
% "broadband" because each subcarrier's IFFT spreads across the whole FFT
% window -- but spectrally the jam energy sits ONLY on the pilot bins.)
%   jam_type=1 : Gaussian noise on the 4 pilot subcarriers.
%   jam_type=2 : random-phase unit-magnitude tones on the 4 pilot bins,
%                modulated by exp(j*2*pi*pilot_cfo_hz*n/fs) so the
%                receiver's per-symbol theta absorbs a fake drift.
if attack_mode == 4
    idx = info.data_start : info.data_end;

    FFT_size  = info.FFT_size;
    cp_size   = info.cp_size;
    sym_len   = info.sym_len;
    sc2idx    = @(k) k + FFT_size/2 + 1;
    pilot_sc  = [-21 -7 7 21];
    pilot_idx = sc2idx(pilot_sc);
    nsyms     = info.num_ofdm_symbols;

    fake_data = zeros(nsyms * sym_len, 1);
    for k = 1:nsyms
        X = zeros(FFT_size, 1);
        if jam_type == 1
            X(pilot_idx) = noise(length(pilot_idx));                % pilot-only noise
        else
            X(pilot_idx) = exp(1j*2*pi*rand(length(pilot_idx),1));  % pilot-only random phase
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
    end

    if jam_type == 1
        jammer(idx) = noise_power     * tx_rms * fake_data;
    else
        jammer(idx) = jam_power_scale * tx_rms * fake_data;
    end
end

%(5) TODO6 : attack lts for channel estimation
% Channel estimate is H[k] = Y[k] / X_known[k] from the LTS.
%   jam_type=1 : noise on the LTS region corrupts Y[k].
%   jam_type=2 : send a fake LTS with every other active subcarrier inverted,
%                so the estimated H is wrong on those bins.
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
        mask = ones(size(lts_val));
        mask(1:2:end) = -1;
        lts_val_fake = lts_val .* mask;
        lts_f = zeros(FFT_size, 1);
        lts_f(lts_sc + FFT_size/2 + 1) = lts_val_fake;
        lts_body = ifft(ifftshift(lts_f), FFT_size);
        lts_fake = [lts_body(end-31:end); lts_body; lts_body];
        lts_fake = lts_fake / rms(lts_fake);
        jammer(idx) = jam_power_scale * tx_rms * lts_fake;
    end
end

%(6) TODO7 : attack CP for circular convolution
% CP makes linear channel convolution behave circularly inside the FFT window.
%   jam_type=1 : noise replaces each CP -> non-periodic content breaks
%                circularity under any multipath.
%   jam_type=2 : replace each CP with the START of an unrelated OFDM body
%                (structured but non-matching), same circularity break.
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

%(7) TODO8 : high-power OFDM data to cover the real data
% Blanket the entire data region with a high-power OFDM jam. Each active
% data subcarrier carries a "flower" symbol r*exp(j*theta) with theta
% uniform in [0, 2*pi) and r = |cos(flower_petals*theta/2)| -- a rose
% curve. After the receiver FFTs the contaminated data symbols, the
% per-subcarrier IQ scatter draws a flower with flower_petals petals,
% which doubles as a visible signature that the jammer is active.
if attack_mode == 7
    idx = info.data_start : info.data_end;
    if jam_type == 1
        jammer(idx) = noise_power * tx_rms * noise(numel(idx));
    else
        FFT_size   = info.FFT_size;
        cp_size    = info.cp_size;
        sym_len    = info.sym_len;
        active_sc  = [-26:-1 1:26];
        sc2idx     = @(k) k + FFT_size/2 + 1;
        active_idx = sc2idx(active_sc);
        nsyms      = info.num_ofdm_symbols;
        num_act    = length(active_sc);

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
%%% GONMAN %%%

%(7.5) Final whole-frame RMS normalization
% Before this step, jammer's whole-frame RMS = active_knob * tx_rms *
% sqrt(region_len / total_len) -- which makes the *displayed* RMS look
% smaller than expected for any attack that only fills part of the frame.
% Renormalize so that rms(jammer) / rms(tx_signal) == active_knob exactly,
% i.e. the knob is a direct whole-frame RMS ratio.
if jam_type == 1
    active_knob = noise_power;
else
    active_knob = jam_power_scale;
end
jam_rms_now = rms(jammer);
if jam_rms_now > 1e-12 && active_knob > 0
    jammer = jammer * (active_knob * tx_rms / jam_rms_now);
end

%(8) Joint clipping protection (B210 input must stay below 1.0)
% Scale BOTH channels by the same factor so that the noise_power /
% jam_power_scale ratio (i.e. the relative power of real vs jammer) is
% preserved -- only the absolute level drops.
clip_limit = 1;
peak_both = max(max(abs(tx_signal)), max(abs(jammer)));
if peak_both > clip_limit
    common_scale = clip_limit / peak_both;
    tx_signal = tx_signal * common_scale;
    jammer    = jammer    * common_scale;
    fprintf('Clipping guard: peak %.3f > %.2f, scaling both channels by %.4f\n', ...
        peak_both, clip_limit, common_scale);
end

%(9) Plot the two TX frames: time-domain + spectrum
% 2x2 layout: time-domain on the left, average per-OFDM-symbol spectrum on
% the right (computed by avg_spectrum: FFT every FFT_size-sample window,
% skip the zero-pad windows, then average |X[k]|^2). The spectrum panels'
% x-axis is the OFDM subcarrier index -32..31 with pilots [-21 -7 7 21]
% drawn in green so attacks like TODO5 (pilot-only) are immediately
% obvious -- only the green stems light up.
t_us_tx     = (0:length(tx_signal)-1).' / fs * 1e6;
sts_mid_us  = t_us_tx(round((info.sts_start  + info.sts_end )/2));
lts_mid_us  = t_us_tx(round((info.lts_start  + info.lts_end )/2));
data_mid_us = t_us_tx(round((info.data_start + info.data_end)/2));

sc_axis    = (-info.FFT_size/2 : info.FFT_size/2 - 1).';
pilot_sc_p = [-21 -7 7 21];
pilot_mask = ismember(sc_axis, pilot_sc_p);

% Linear magnitude |X[k]| (sqrt of avg_spectrum which returns |X|^2)
spec_tx_mag  = sqrt(avg_spectrum(tx_signal, info));
spec_jam_mag = sqrt(avg_spectrum(jammer,    info));

% Common y-limit so empty bins read as 0 and the lit subcarriers stay tall.
spec_top  = max([spec_tx_mag; spec_jam_mag]);
spec_ylim = [0, spec_top * 1.1 + eps];

fig_tx = figure('Name','TX frames: time + spectrum','NumberTitle','off');

% ---- (1,1) TX time-domain ----
ax_tx_t = subplot(2,2,1);
plot(t_us_tx, real(tx_signal), 'b'); grid on; hold on;
for x_idx = [info.sts_start, info.lts_start, info.data_start, info.data_end]
    xline(t_us_tx(x_idx), 'k--');
end
% Labels at the BOTTOM of the panel so they don't crash into the title.
% STS / DATA share the lower row; LTS sits one stagger above so adjacent
% labels don't horizontally collide on short frames.
yl = ylim; yspan = yl(2) - yl(1);
text(sts_mid_us,  yl(1)+0.08*yspan, 'STS',  ...
    'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
text(lts_mid_us,  yl(1)+0.22*yspan, 'LTS',  ...
    'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
text(data_mid_us, yl(1)+0.08*yspan, 'DATA', ...
    'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
xlabel('Time (\mus)'); ylabel('Re\{tx ch 1\}');
title(sprintf('TX ch 1 time-domain  (RMS=%.3f, peak=%.3f)', ...
    rms(tx_signal), max(abs(tx_signal))));

% ---- (1,2) TX spectrum ----
subplot(2,2,2);
stem(sc_axis(~pilot_mask), spec_tx_mag(~pilot_mask), 'b', 'filled'); hold on;
stem(sc_axis( pilot_mask), spec_tx_mag( pilot_mask), 'g', 'filled');
grid on;
xlim([sc_axis(1), sc_axis(end)]); ylim(spec_ylim);
xlabel('Subcarrier index'); ylabel('|X[k]|');
legend('data / null sc','pilot sc','Location','best');
title('TX ch 1 spectrum  (avg over OFDM-sized windows)');

% ---- (2,1) jammer time-domain ----
ax_jam_t = subplot(2,2,3);
plot(t_us_tx, real(jammer), 'r'); grid on; hold on;
for x_idx = [info.sts_start, info.lts_start, info.data_start, info.data_end]
    xline(t_us_tx(x_idx), 'k--');
end
yl = ylim; yspan = yl(2) - yl(1);
if yspan > 0
    text(sts_mid_us,  yl(1)+0.08*yspan, 'STS',  ...
        'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
    text(lts_mid_us,  yl(1)+0.22*yspan, 'LTS',  ...
        'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
    text(data_mid_us, yl(1)+0.08*yspan, 'DATA', ...
        'FontWeight','bold','HorizontalAlignment','center','BackgroundColor','w');
end
xlabel('Time (\mus)'); ylabel('Re\{tx ch 2\}');
title(sprintf('TX ch 2 jammer time-domain  (mode=%d, type=%d, RMS=%.3f, peak=%.3f)', ...
    attack_mode, jam_type, rms(jammer), max(abs(jammer))));

% ---- (2,2) jammer spectrum ----
subplot(2,2,4);
stem(sc_axis(~pilot_mask), spec_jam_mag(~pilot_mask), 'r', 'filled'); hold on;
stem(sc_axis( pilot_mask), spec_jam_mag( pilot_mask), 'g', 'filled');
grid on;
xlim([sc_axis(1), sc_axis(end)]); ylim(spec_ylim);
xlabel('Subcarrier index'); ylabel('|X[k]|');
legend('data / null sc','pilot sc','Location','best');
title('TX ch 2 jammer spectrum  (avg over OFDM-sized windows)');

linkaxes([ax_tx_t, ax_jam_t], 'x');

%%% ===== Local functions ===== %%%

function S = avg_spectrum(x, info)
% avg_spectrum
%   Average OFDM-aligned magnitude-squared spectrum over the data region.
%   For each OFDM symbol slot in [info.data_start .. info.data_end] the
%   16-sample CP is skipped and only the 64-sample body is FFTed (with
%   fftshift). This alignment matters: if you FFT an arbitrary 64-sample
%   chunk that straddles a CP/body boundary, a single-subcarrier signal
%   (e.g. the pilot-only jammer) appears to leak across all bins.
%   Empty-energy bodies (when the jammer doesn't touch the data region,
%   like STS/LTS attacks) are skipped so they don't average toward zero.
    x = x(:);
    FFT_size = info.FFT_size;
    cp_size  = info.cp_size;
    sym_len  = info.sym_len;

    P   = zeros(FFT_size, 1);
    cnt = 0;
    for k = 0:info.num_ofdm_symbols - 1
        body_start = info.data_start + k*sym_len + cp_size;
        body_end   = body_start + FFT_size - 1;
        if body_end > length(x), break; end

        body = x(body_start : body_end);
        if rms(body) > 1e-10
            P   = P   + abs(fftshift(fft(body, FFT_size))).^2;
            cnt = cnt + 1;
        end
    end

    if cnt > 0
        S = P / cnt;
    else
        S = P;
    end
end

function [tx_frame, info] = gen_80211ag_frame(num_ofdm_symbols, qam_num)
% One-shot 802.11a/g-like frame generator.
% Returns a single column-vector frame [pad; STS; LTS; OFDM data; pad]
% plus an info struct giving the index range of every region.

    pad_len  = 100;
    FFT_size = 64;
    cp_size  = 16;

    sts = gen_sts();              sts = sts / rms(sts);
    lts = gen_lts();              lts = lts / rms(lts);

    [ofdm_data, ~, ~, ~] = gen_ofdm_data(num_ofdm_symbols, qam_num);
    ofdm_data = ofdm_data / rms(ofdm_data);

    tx_frame = [
        zeros(pad_len, 1);
        sts;
        lts;
        ofdm_data;
        zeros(pad_len, 1)
    ];

    % Region indices
    sym_len    = FFT_size + cp_size;
    sts_start  = pad_len + 1;
    sts_end    = sts_start + length(sts) - 1;
    lts_start  = sts_end + 1;
    lts_end    = lts_start + length(lts) - 1;
    data_start = lts_end + 1;
    data_end   = data_start + num_ofdm_symbols * sym_len - 1;

    cp_starts  = data_start + (0:num_ofdm_symbols-1) * sym_len;

    info.pad_len          = pad_len;
    info.FFT_size         = FFT_size;
    info.cp_size          = cp_size;
    info.sym_len          = sym_len;
    info.num_ofdm_symbols = num_ofdm_symbols;
    info.qam_num          = qam_num;
    info.sts_start        = sts_start;
    info.sts_end          = sts_end;
    info.lts_start        = lts_start;
    info.lts_end          = lts_end;
    info.lts_body_start   = lts_start + 32;        % first 64-sample LTS body
    info.data_start       = data_start;
    info.data_end         = data_end;
    info.cp_starts        = cp_starts;             % 1xN starting index of each CP
end

function sts = gen_sts()
    FFT_size = 64;
    short_sc = [-24 -20 -16 -12 -8 -4 4 8 12 16 20 24];
    sts_val = sqrt(13/6) * ...
        [1+1j, -1-1j,  1+1j, -1-1j, -1-1j,  1+1j, ...
         -1-1j, -1-1j, 1+1j,  1+1j,  1+1j,  1+1j];
    sts_f = zeros(FFT_size, 1);
    sts_f(short_sc + FFT_size/2 + 1) = sts_val;
    sts_64 = ifft(ifftshift(sts_f), FFT_size);
    sts_16 = sts_64(1:16);
    sts = repmat(sts_16, 10, 1);
end

function lts = gen_lts()
    FFT_size = 64;
    lts_sc = -26:26;
    lts_val = [1,  1, -1, -1,  1,  1, -1,  1, -1,  1,  1,  1,  1,  1,  1, ...
              -1, -1,  1,  1, -1,  1, -1,  1,  1,  1,  1,  0,  1, -1, -1, ...
               1,  1, -1,  1, -1,  1, -1, -1, -1, -1, -1,  1,  1, -1, -1, ...
               1, -1,  1, -1,  1,  1,  1,  1];
    lts_f = zeros(FFT_size, 1);
    lts_f(lts_sc + FFT_size/2 + 1) = lts_val;
    lts_64 = ifft(ifftshift(lts_f), FFT_size);
    lts = [lts_64(end-31:end); lts_64; lts_64];
end

function [x_cp, data_bits, data_sym, pilot_sym] = gen_ofdm_symbol(qam_num)
    FFT_size = 64;
    cp_size  = 16;
    active_sc = [-26:-1 1:26];
    pilot_sc  = [-21 -7 7 21];
    data_sc   = setdiff(active_sc, pilot_sc);

    pilot_bits = randi([0 1], length(pilot_sc), 1);
    pilot_sym  = 2*pilot_bits - 1;

    bit       = log2(qam_num);
    data_bits = randi([0 1], length(data_sc)*bit, 1);
    data_sym  = qammod(data_bits, qam_num, ...
                       'InputType', 'bit', 'UnitAveragePower', true);

    Xc = zeros(FFT_size, 1);
    sc2idx = @(k) k + FFT_size/2 + 1;
    for i = 1:length(pilot_sc)
        Xc(sc2idx(pilot_sc(i))) = pilot_sym(i);
    end
    for i = 1:length(data_sc)
        Xc(sc2idx(data_sc(i))) = data_sym(i);
    end

    a = ifft(ifftshift(Xc));
    x_cp = [a(end-cp_size+1:end); a];
end

function [ofdm_data, tx_bits, tx_data_syms, pilot_syms] = gen_ofdm_data(num_ofdm_symbols, qam_num)
    active_sc = [-26:-1 1:26];
    pilot_sc  = [-21 -7 7 21];
    data_sc   = setdiff(active_sc, pilot_sc);
    FFT_size  = 64;
    cp_size   = 16;
    num_data  = length(data_sc);
    num_pilot = length(pilot_sc);

    tx_bits      = zeros(log2(qam_num)*num_data, num_ofdm_symbols);
    tx_data_syms = zeros(num_data, num_ofdm_symbols);
    pilot_syms   = zeros(num_pilot, num_ofdm_symbols);
    ofdm_data    = zeros((FFT_size + cp_size) * num_ofdm_symbols, 1);

    for sym_idx = 1:num_ofdm_symbols
        [x_cp, data_bits, data_sym, pilot_sym] = gen_ofdm_symbol(qam_num);
        s = (sym_idx - 1) * (FFT_size + cp_size) + 1;
        e = sym_idx * (FFT_size + cp_size);
        ofdm_data(s:e)           = x_cp;
        tx_bits(:, sym_idx)      = data_bits;
        tx_data_syms(:, sym_idx) = data_sym;
        pilot_syms(:, sym_idx)   = pilot_sym;
    end
end
