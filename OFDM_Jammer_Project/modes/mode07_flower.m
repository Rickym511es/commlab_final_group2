function m = mode07_flower()
% mode07_flower  TODO8 - high-power OFDM data overlay (rose-curve "flower").
%   type 1: noise across the data region.
%   type 2: per-active-subcarrier r*exp(j*theta) with theta uniform and
%           r = |cos(flower_petals * theta / 2)| (a rose curve). The flower
%           is a visible signature in the RX constellation.
    m.id    = 7;
    m.todo  = 'TODO8 高功率資料覆蓋 (flower)';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(jam_type, ~, tx_signal, info, ~, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    idx = info.data_start : info.data_end;
    if jam_type == 1
        jammer(idx) = knob.noise_power * tx_rms * cnoise(numel(idx));
    else
        FFT_size  = info.FFT_size; cp_size = info.cp_size; sym_len = info.sym_len;
        active_sc = [-26:-1 1:26];
        sc2idx    = @(k) k + FFT_size/2 + 1;
        active_idx= sc2idx(active_sc);
        nsyms     = info.num_ofdm_symbols; num_act = length(active_sc);

        fake_data = zeros(nsyms * sym_len, 1);
        for n = 1:nsyms
            theta   = 2*pi*rand(num_act, 1);
            r       = abs(cos(knob.flower_petals * theta / 2));
            symbols = r .* exp(1j*theta);
            X = zeros(FFT_size, 1);
            X(active_idx) = symbols;
            x_time = ifft(ifftshift(X), FFT_size);
            x_cp   = [x_time(end-cp_size+1:end); x_time];
            s = (n-1)*sym_len + 1;
            fake_data(s : s+sym_len-1) = x_cp;
        end
        fake_data = fake_data / rms(fake_data);
        jammer(idx) = knob.jam_power_scale * tx_rms * fake_data;
    end
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
