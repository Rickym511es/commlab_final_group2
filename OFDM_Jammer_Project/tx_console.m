function tx_console(mode, power, varargin)
% tx_console  B210 transmitter entry point.
%
%   tx_console()                          - run the full timed schedule
%   tx_console(mode)                      - pin a single attack id (0..12)
%   tx_console(mode, power)               - pin a single attack, scale jammer power
%   tx_console(mode, power, name, value, ...)
%       - additional name-value overrides applied to params.knob before
%         the schedule is built. Recognized names:
%             'bw_ratio'  scalar in [0,1]   -> knob.awgn_bw_ratio   (mode 9)
%             'freq'      scalar (Hz)       -> knob.single_tone_freq (mode 10)
%             'freqs'     vector (Hz)       -> knob.multi_tone_freqs (mode 11)
%             'amps'      vector            -> knob.multi_tone_amps  (mode 11)
%
%   Example:
%       tx_console(7, 2)                                 % flower at 2x power
%       tx_console(9, 1.5, 'bw_ratio', 0.3)              % narrow AWGN at 1.5x
%       tx_console(10, 1, 'freq', 200e3)                 % CW at 200 kHz
%       tx_console(11, 1, 'freqs', [80e3 160e3], ...
%                           'amps',  [1 1])              % two custom tones
%
%   A single `power` arg scales both knob.noise_power and knob.jam_power_scale,
%   so it is a direct whole-frame RMS multiple of the real frame regardless
%   of jam_type (noise vs structured).
    addpath(genpath(fileparts(mfilename('fullpath'))));
    params = load_parameters();

    pinnedMode = [];
    if nargin >= 1 && ~isempty(mode), pinnedMode = mode; end
    if nargin >= 2 && ~isempty(power)
        params.knob.noise_power     = power;
        params.knob.jam_power_scale = power;
    end
    params.knob = apply_knob_overrides(params.knob, varargin);

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
