function rx_burst_console(mode, burstOpts)
% rx_burst_console  N210 receiver, burst-scoring variant.
%   rx_burst_console(mode)             - lock RX cfg to that jammer mode
%   rx_burst_console(mode, burstOpts)  - override burst.rxFramesPerReport etc
%
% Difference vs rx_console:
%   * Locks to a single mode's rxcfg (since tx_burst_console pins one).
%   * Accumulates per-burst stats: every rxFramesPerReport DETECTED
%     frames forms one "RX burst" - we print mean SNR/BER for that
%     bucket plus running cumulative bits/errors.
%   * Burst boundaries on RX are detected-frame counts (not wall clock):
%     this stays meaningful even if some TX frames are lost to jamming,
%     and avoids fragile TX<->RX clock sync.
%
% Stops at params.sched.runSeconds (same as rx_console).

    addpath(genpath(fileparts(mfilename('fullpath'))));

    if nargin < 1 || isempty(mode)
        error('rx_burst_console: mode is required (0..12).');
    end
    if nargin < 2, burstOpts = struct(); end

    params = load_parameters();
    burst  = merge_opts(default_burst_opts(), burstOpts);

    sched = mode_registry('schedule', params, mode);
    if isempty(sched)
        error('rx_burst_console: no schedule entry for mode %d.', mode);
    end
    phase = sched(1);

    rx = init_usrp_rx(params);
    c = onCleanup(@() safe_release(rx));
    run_rx_burst(params, burst, phase, rx);
end

function out = merge_opts(base, override)
    out = base;
    if isempty(override) || ~isstruct(override), return; end
    f = fieldnames(override);
    for i = 1:numel(f), out.(f{i}) = override.(f{i}); end
end

function safe_release(obj)
    try, release(obj); catch, end
end
