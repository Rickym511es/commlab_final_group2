function H = estimate_channel(rx_lts, lts_f_known)
% estimate_channel  H[k] = Y[k] / X_known[k] per active subcarrier.
    rx_lts_f = fftshift(fft(rx_lts));
    H = zeros(size(rx_lts_f));
    v = abs(lts_f_known) > 1e-12;
    H(v) = rx_lts_f(v) ./ lts_f_known(v);
end
