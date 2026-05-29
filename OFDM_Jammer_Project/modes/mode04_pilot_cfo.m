function m = mode04_pilot_cfo()
% mode04_pilot_cfo  TODO5 - attack pilots for CFO.
%   Energizes ONLY the 4 pilot subcarriers across the data region. The RX
%   per-symbol pilot phase-tracker absorbs the injected drift.
%     type 1: Gaussian noise on the 4 pilot bins (no drift, just confusion).
%     type 2: random-phase unit tones on the 4 pilot bins, modulated by
%             exp(j*2*pi*pilot_cfo_hz*n/fs) to inject a fake drift.
    m.id    = 4;
    m.todo  = 'TODO5 pilot CFO 攻擊';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(jam_type, ~, tx_signal, info, fs, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    idx = info.data_start : info.data_end;
    FFT_size = info.FFT_size; cp_size = info.cp_size; sym_len = info.sym_len;
    sc2idx    = @(k) k + FFT_size/2 + 1;
    pilot_idx = sc2idx([-21 -7 7 21]);
    nsyms     = info.num_ofdm_symbols;

    fake_data = zeros(nsyms * sym_len, 1);
    for k = 1:nsyms
        X = zeros(FFT_size, 1);
        if jam_type == 1
            X(pilot_idx) = cnoise(length(pilot_idx));
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
        fake_data = fake_data .* exp(1j*2*pi*knob.pilot_cfo_hz*n_data/fs);
        jammer(idx) = knob.jam_power_scale * tx_rms * fake_data;
    else
        jammer(idx) = knob.noise_power * tx_rms * fake_data;
    end
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
