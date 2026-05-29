function m = mode12_fake_frame()
% mode12_fake_frame  TODO12 - full-frame overlay with an independent fake frame.
%   Builds [pad; STS; LTS; fake_ofdm; pad] using a fixed RNG seed (999) so the
%   fake payload is reproducible but does not collide with the real frame seed.
    m.id    = 12;
    m.todo  = 'TODO12 假 Frame 覆蓋';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, info, ~, knob)
    N = length(tx_signal);
    tx_rms = rms(tx_signal);
    pad_len  = info.sts_start - 1;
    fake_sts = gen_sts();
    fake_lts = gen_lts();
    prev_state = rng; rng(999);
    [fake_ofdm, ~, ~, ~] = gen_ofdm_data(info.num_ofdm_symbols, info.qam_num);
    rng(prev_state);
    fake_frame = [zeros(pad_len,1); fake_sts; fake_lts; fake_ofdm; zeros(pad_len,1)];
    if length(fake_frame) ~= N
        fake_frame = [fake_frame; zeros(max(0, N - length(fake_frame)), 1)];
        fake_frame = fake_frame(1:N);
    end
    fake_frame = knob.jam_power_scale * tx_rms * fake_frame / rms(fake_frame);
    jammer = fake_frame;
end
