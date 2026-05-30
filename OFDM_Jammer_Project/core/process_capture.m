function res = process_capture(data, sts, lts, frame_len, spec, fs, ...
                                 tx_bits, tx_data_syms, pilot_syms, ...
                                 lts_f_known, detectRatio, rxOpt)
% process_capture  Run one capture through the Lab 5-style receive chain:
%   STS detect -> coarse/fine CFO -> LTS channel estimate -> equalize ->
%   pilot phase correction -> QAM demap -> BER + EVM-like SNR.
%
% rxOpt fields (set by the active mode's rxcfg):
%   .detectorMode      'mf' | 'autocorr'
%   .autocorrThreshold autocorr threshold
%   .doCoarseCFO       skip when STS is the attack target
%   .doFineCFO         skip when LTS channel-est is the attack target
%   .ltsCopyForH       1 | 2 | 0 (avg) - which LTS copy estimates H
    res.detected = false;  res.eq_data_syms = []; res.eq_raw_syms = [];
    res.ber = NaN; res.snr_dB = NaN;
    res.cfo_hz = NaN; res.fine_cfo_hz = NaN; res.detect_score = NaN; res.ratio = NaN;
    res.crc_pass = false;

    data = data(:);
    FFT_size = spec.FFT_size;  cp_size = spec.cp_size;  pad_len = spec.pad_len;
    qam_num  = spec.qam_num;

    switch rxOpt.detectorMode
        case 'autocorr'
            det = detect_sts_autocorr(data, length(sts), pad_len, rxOpt.autocorrThreshold);
        otherwise
            det = detect_sts_mf(data, sts, pad_len, detectRatio);
    end
    res.detect_score = det.score;
    res.ratio        = det.score;
    if ~det.detected, return; end

    frame_start = det.frame_start;
    frame_end   = frame_start + frame_len - 1;
    if frame_start < 1 || frame_end > length(data), return; end

    rx_frame = data(frame_start:frame_end);
    rx_frame = rx_frame - mean(rx_frame);
    n = (0:length(rx_frame)-1).';

    cfo_total = 0;
    if rxOpt.doCoarseCFO
        D = 16;
        rx_sts = rx_frame(pad_len+1 : pad_len+length(sts));
        Pc = sum(conj(rx_sts(1:end-D)) .* rx_sts(1+D:end));
        cfo_coarse = angle(Pc) * fs / (2*pi*D);
        cfo_total  = cfo_total + cfo_coarse;
        res.cfo_hz = cfo_coarse;
    else
        res.cfo_hz = 0;
    end
    rx_cfo = rx_frame .* exp(-1j*2*pi*cfo_total*n/fs);

    first_lts = pad_len + length(sts) + 33;
    rx_lts1 = rx_cfo(first_lts            : first_lts + FFT_size - 1);
    rx_lts2 = rx_cfo(first_lts + FFT_size : first_lts + 2*FFT_size - 1);

    if rxOpt.doFineCFO
        Pf = sum(conj(rx_lts1) .* rx_lts2);
        cfo_fine = angle(Pf) * fs / (2*pi*FFT_size);
        cfo_total = cfo_total + cfo_fine;
        res.fine_cfo_hz = cfo_fine;
        rx_cfo  = rx_frame .* exp(-1j*2*pi*cfo_total*n/fs);
        rx_lts1 = rx_cfo(first_lts            : first_lts + FFT_size - 1);
        rx_lts2 = rx_cfo(first_lts + FFT_size : first_lts + 2*FFT_size - 1);
    else
        res.fine_cfo_hz = 0;
    end

    H1 = estimate_channel(rx_lts1, lts_f_known);
    H2 = estimate_channel(rx_lts2, lts_f_known);
    switch rxOpt.ltsCopyForH
        case 1,    H = H1;
        case 2,    H = H2;
        otherwise, H = (H1 + H2) / 2;
    end

    sc2idx   = @(k) k + FFT_size/2 + 1;
    data_idx = sc2idx(spec.data_sc);
    pilot_idx= sc2idx(spec.pilot_sc);
    data_start = pad_len + length(sts) + length(lts) + 1;
    sym_len = FFT_size + cp_size;

    num_ofdm = spec.num_ofdm;
    eq_data = zeros(length(spec.data_sc), num_ofdm);
    eq_raw  = zeros(length(spec.data_sc), num_ofdm);
    for k = 1:num_ofdm
        seg = rx_cfo(data_start+(k-1)*sym_len : data_start+k*sym_len-1);
        Y = ofdm_demod_symbol(seg, FFT_size, cp_size);
        X = equalize_symbol(Y, H);
        eq_raw(:,k) = X(data_idx);
        theta = angle(sum(X(pilot_idx) .* conj(pilot_syms(:,k))));
        X = X * exp(-1j*theta);
        d = X(data_idx);
        d(~isfinite(d)) = 0;
        p = mean(abs(d).^2);
        if isfinite(p) && p > 1e-12, d = d / sqrt(p); else, d = zeros(size(d)); end
        eq_data(:,k) = d(:);
    end
    rr = eq_raw(:); rr(~isfinite(rr)) = 0;
    pr = mean(abs(rr).^2);
    if isfinite(pr) && pr > 1e-12, eq_raw = eq_raw / sqrt(pr); end

    rx_bits = zeros(size(tx_bits));
    for k = 1:num_ofdm
        s = eq_data(:,k); s(~isfinite(s)) = 0;
        rx_bits(:,k) = qamdemod(s, qam_num, 'OutputType','bit','UnitAveragePower',true);
    end
    res.ber = sum(rx_bits(:) ~= tx_bits(:)) / numel(tx_bits);

    % CRC-16 over the recovered user-payload bits (the trailing
    % spec.crc_len bits in column-major order are the CRC tail).
    rx_bit_stream = rx_bits(:);
    if spec.crc_len > 0 && numel(rx_bit_stream) > spec.crc_len
        rx_user = rx_bit_stream(1 : end - spec.crc_len);
        rx_crc  = rx_bit_stream(end - spec.crc_len + 1 : end);
        recomp  = compute_crc16(rx_user);
        res.crc_pass = isequal(rx_crc(:), recomp(:));
    else
        res.crc_pass = (res.ber == 0);   % no CRC configured -> fall back to BER
    end

    rxv = eq_data(:);  txv = tx_data_syms(:);
    m = min(numel(rxv),numel(txv));
    err = rxv(1:m) - txv(1:m);
    res.snr_dB = 10*log10(mean(abs(txv(1:m)).^2) / (mean(abs(err).^2)+1e-12));

    res.detected = true;
    res.eq_data_syms = eq_data;
    res.eq_raw_syms  = eq_raw;
end
