function feed_jam_const(cd_jam, jammer, info)
% feed_jam_const  Project jammer time-domain into the data-subcarrier
% frequency-domain symbols and feed the constellation diagram. Used by the
% TX-side live display so TODO8 (high-power data overlay) shows as a clean
% flower in the jammer-only constellation; STS/LTS attacks leave it blank.
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
    if p > 1e-9, cd_jam(S(:) / p); end
end
