function [x_cp, data_bits, data_sym, pilot_sym] = gen_ofdm_symbol(qam_num)
% gen_ofdm_symbol  One OFDM symbol with CP. 48 data + 4 pilot subcarriers.
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
