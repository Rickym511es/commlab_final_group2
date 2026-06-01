function rx_console(mode, varargin)
% rx_console  N210 receiver entry point.
%
%   rx_console()                          - monitor the full timed schedule
%   rx_console(mode)                      - lock RX to one attack id's rxcfg
%   rx_console(mode, name, value, ...)    - mirror the same name-value knob
%                                           overrides as tx_console so the
%                                           label printed by the dashboard
%                                           reflects the same parameters.
%
%   RX has no `power` knob - it just observes whatever the TX puts on the
%   air. Setting `mode` here ensures the RX strategy matches a single-mode
%   TX run (the phase-by-time alignment doesn't apply when TX is pinned).
%   Recognized names: 'bw_ratio', 'freq', 'freqs', 'amps' (same as TX).
    addpath(genpath(fileparts(mfilename('fullpath'))));
    params = load_parameters();

    pinnedMode = [];
    if nargin >= 1 && ~isempty(mode), pinnedMode = mode; end
    params.knob = apply_knob_overrides(params.knob, varargin);

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
