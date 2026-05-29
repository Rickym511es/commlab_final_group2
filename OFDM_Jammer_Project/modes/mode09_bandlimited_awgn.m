function m = mode09_bandlimited_awgn()
% mode09_bandlimited_awgn  TODO9-2 - band-limited AWGN (BW sweep).
%   Injects complex noise in a frequency window of width
%   round(N * knob.awgn_bw_ratio(bw_idx)) bins centered around DC.
%   Direct N-point frequency-domain construction avoids the periodicity
%   artifacts of the older ifft(64)+repmat approach.
    m.id    = 9;
    m.todo  = 'TODO9-2 限頻 AWGN';
    m.types = [2];
    m.sweep = 'awgn_bw_ratio';   % schedule iterates 1..length(knob.awgn_bw_ratio)
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, bw_idx, tx_signal, ~, ~, knob)
    N = length(tx_signal);
    tx_rms = rms(tx_signal);
    if bw_idx >= 1 && bw_idx <= length(knob.awgn_bw_ratio)
        bw_ratio = knob.awgn_bw_ratio(bw_idx);
    else
        bw_ratio = knob.awgn_bw_ratio(1);
    end
    bw_bins  = max(1, round(N * bw_ratio));
    center   = floor(N/2) + 1;
    bin_lo   = max(1, center - floor(bw_bins/2));
    bin_hi   = min(N, bin_lo + bw_bins - 1);
    bins     = bin_lo:bin_hi;
    noise_fd = zeros(N, 1);
    noise_fd(bins) = (randn(numel(bins),1) + 1j*randn(numel(bins),1)) / sqrt(2);
    noise_td = ifft(ifftshift(noise_fd));
    jammer   = knob.jam_power_scale * tx_rms * noise_td;
end
