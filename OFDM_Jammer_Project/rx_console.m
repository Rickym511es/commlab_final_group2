function rx_console(mode)
% rx_console  N210 receiver entry point.
%   rx_console()      - monitor the full timed schedule
%   rx_console(mode)  - lock RX to one attack id's rxcfg (for single-mode TX runs)
%
% RX has no `power` knob - it just observes whatever the TX puts on the air.
% Setting `mode` here ensures the RX strategy (pickRxConfig analog) matches
% a single-mode TX run, since the phase-by-time alignment doesn't apply when
% TX is pinned.
    addpath(genpath(fileparts(mfilename('fullpath'))));
    params = load_parameters();

    pinnedMode = [];
    if nargin >= 1 && ~isempty(mode), pinnedMode = mode; end

    sched = mode_registry('schedule', params, pinnedMode);
    if isempty(sched)
        error('No phases scheduled. Check mode id and load_parameters() defaults.');
    end

    rx = init_usrp_rx(params);
    c = onCleanup(@() safe_release(rx));
    run_rx_loop(params, sched, rx);
end

function safe_release(obj)
    try, release(obj); catch, end
end
