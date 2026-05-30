function m = mode09_bandlimited_awgn()
% mode09_bandlimited_awgn  TODO9-2 - band-limited AWGN.
%   Injects complex noise in a frequency window of width
%   round(N * knob.awgn_bw_ratio) bins centered around DC.
%
%   The fixed [0.2 0.5 1.0] sweep was removed - knob.awgn_bw_ratio is now
%   a single scalar set by load_parameters or overridden at the console
%   call site, e.g. tx_console(9, 1, 'bw_ratio', 0.3).
%   To compare multiple bandwidths, call tx_console multiple times.
    m.id    = 9;
    m.todo  = 'TODO9-2 限頻 AWGN';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, ~, knob)
    N = length(tx_signal);
    tx_rms = rms(tx_signal);
    bw_ratio = max(0, min(1, knob.awgn_bw_ratio(1)));   % clamp [0,1]
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
