function lts = gen_lts()
% gen_lts  Generate one 160-sample 802.11a/g LTS: [CP32 | body64 | body64].
    FFT_size = 64;
    lts_sc = -26:26;
    lts_val = [1,1,-1,-1,1,1,-1,1,-1,1,1,1,1,1,1,-1,-1,1,1,-1,1,-1,1,1,1,1, ...
               0,1,-1,-1,1,1,-1,1,-1,1,-1,-1,-1,-1,-1,1,1,-1,-1,1,-1,1,-1,1,1,1,1];
    lts_f = zeros(FFT_size,1);
    lts_f(lts_sc + FFT_size/2 + 1) = lts_val;
    lts_64 = ifft(ifftshift(lts_f), FFT_size);
    lts = [lts_64(end-31:end); lts_64; lts_64];
end
