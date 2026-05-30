function tx_burst_console(mode, burstOpts, power)
% tx_burst_console  B210 transmitter, burst-orchestrated variant.
%   tx_burst_console(mode)                  - single jammer mode, default burst opts
%   tx_burst_console(mode, burstOpts)       - override any burst.* field via struct
%   tx_burst_console(mode, burstOpts, power)- also scale jammer power
%
% Difference vs tx_console:
%   * Forces a single jammer mode (0..12); no multi-phase schedule.
%   * TX channel is duty-cycled (framesPerBurst on, period-rest off) so
%     each burst is an isolated "transmission" you can score with RX.
%   * Jammer firing pattern decouples from TX duty:
%       'continuous'  - always on
%       'periodic'    - jamOnFrames/jamPeriodFrames (optionally TX-aligned)
%       'random'      - per-frame Bernoulli, prob jamRandomProb
%       'single_shot' - fire only on burst index singleShotBurst
%
% mode 0 means "no jammer ever" - just exercises the bursty TX itself.
%
% See config/default_burst_opts.m for all knobs; pass any subset to override.

    addpath(genpath(fileparts(mfilename('fullpath'))));

    if nargin < 1 || isempty(mode)
        error('tx_burst_console: mode is required (0..12). Use 0 for no jammer.');
    end
    if nargin < 2, burstOpts = struct(); end
    if nargin < 3, power = []; end

    params = load_parameters();
    if ~isempty(power)
        params.knob.noise_power     = power;
        params.knob.jam_power_scale = power;
    end

    burst = merge_opts(default_burst_opts(), burstOpts);

    % single-mode schedule (one phase only; we just need its descriptor)
    sched = mode_registry('schedule', params, mode);
    if isempty(sched)
        error('tx_burst_console: no schedule entry for mode %d.', mode);
    end
    phase = sched(1);   % first allowed type/bw of that mode

    tx = init_usrp_tx(params);
    c = onCleanup(@() safe_release(tx));
    run_tx_burst(params, burst, phase, tx);
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
