function sts = gen_sts()
% gen_sts  Generate one full 160-sample 802.11a/g STS (10 repeats of 16).
    FFT_size = 64;
    short_sc = [-24 -20 -16 -12 -8 -4 4 8 12 16 20 24];
    sts_val = sqrt(13/6) * ...
        [1+1j,-1-1j,1+1j,-1-1j,-1-1j,1+1j,-1-1j,-1-1j,1+1j,1+1j,1+1j,1+1j];
    sts_f = zeros(FFT_size,1);
    sts_f(short_sc + FFT_size/2 + 1) = sts_val;
    sts_64 = ifft(ifftshift(sts_f), FFT_size);
    sts = repmat(sts_64(1:16), 10, 1);
end
