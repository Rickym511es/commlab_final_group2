function m = mode04_pilot_cfo()
% mode04_pilot_cfo  TODO5 - attack pilots.
%   Energizes ONLY the 4 pilot subcarriers across the data region with
%   complex Gaussian noise on each OFDM symbol. The RX per-symbol pilot
%   phase-tracker is confused because the pilots no longer carry their
%   expected BPSK values.
%
%   The earlier "structured" variant (unit-magnitude random-phase tones on
%   pilots with a deliberate CFO drift) was removed - it did not add
%   information beyond what the noise variant already achieves.
    m.id    = 4;
    m.todo  = 'TODO5 pilot CFO 攻擊';
    m.types = [1];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, info, ~, knob)
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
        X(pilot_idx) = cnoise(length(pilot_idx));
        x_time = ifft(ifftshift(X), FFT_size);
        x_cp   = [x_time(end-cp_size+1:end); x_time];
        s = (k-1)*sym_len + 1;
        fake_data(s : s+sym_len-1) = x_cp;
    end
    fake_data   = fake_data / rms(fake_data);
    jammer(idx) = knob.noise_power * tx_rms * fake_data;
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
