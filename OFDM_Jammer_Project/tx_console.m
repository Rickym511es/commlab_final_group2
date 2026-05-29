function tx_console(mode, power)
% tx_console  B210 transmitter entry point.
%   tx_console()                - run the full timed schedule
%   tx_console(mode)            - pin a single attack id (0..12) at default power
%   tx_console(mode, power)     - pin a single attack, scale jammer power
%
% A single `power` arg scales both knob.noise_power and knob.jam_power_scale,
% so it is a direct whole-frame RMS multiple of the real frame regardless of
% jam_type (1=noise vs 2=structured).
    addpath(genpath(fileparts(mfilename('fullpath'))));
    params = load_parameters();

    pinnedMode = [];
    if nargin >= 1 && ~isempty(mode), pinnedMode = mode; end
    if nargin >= 2 && ~isempty(power)
        params.knob.noise_power     = power;
        params.knob.jam_power_scale = power;
    end

    sched = mode_registry('schedule', params, pinnedMode);
    if isempty(sched)
        error('No phases scheduled. Check mode id and load_parameters() defaults.');
    end

    tx = init_usrp_tx(params);
    c = onCleanup(@() safe_release(tx));
    run_tx_loop(params, sched, tx);
end

function safe_release(obj)
    try, release(obj); catch, end
end
