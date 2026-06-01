function jammer_C_console(mode, power, reactive)
% jammer_C_console  Node C (USRP3) entry point: reactive jammer (TX+RX, TDD).
%
%   jammer_C_console()                 - use load_parameters_3node defaults
%   jammer_C_console(mode)             - override attack id (0..12)
%   jammer_C_console(mode, power)      - also set digital power scale
%   jammer_C_console(mode, power, reactive) - reactive true/false
%
%   C is the unknown attacker. On ONE N210 it cannot transmit and receive at
%   the same time in MATLAB, so "reactive" is listen-then-talk (TDD):
%       sense A's preamble -> if channel busy, fire a jammer burst -> sense.
%   With reactive=false it falls back to a periodic duty-cycled jammer.
%
%   NOTE: C and A are independent radios, so the jammer is NOT sample-aligned
%   to A's on-air frame at B. Alignment-free attacks (8/9/10/11 + noise) are
%   the meaningful ones here; structured attacks (1-7,12) are best-effort
%   (built from a reference frame, coarsely timed off C's own detection).
    add_paths_3node();
    params = load_parameters_3node();

    if nargin >= 1 && ~isempty(mode),     params.C.react.jammerMode = mode;     end
    if nargin >= 2 && ~isempty(power)
        params.C.react.power        = power;
        params.knob.noise_power     = power;
        params.knob.jam_power_scale = power;
    end
    if nargin >= 3 && ~isempty(reactive), params.C.react.reactive   = logical(reactive); end

    run_jammer_C(params);
end
