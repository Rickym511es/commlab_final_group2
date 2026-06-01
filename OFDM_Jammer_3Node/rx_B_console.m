function rx_B_console()
% rx_B_console  Node B (USRP1) entry point: victim receiver / link monitor.
%
%   B is the honest receiver of A's signal. It does NOT know whether or how
%   C is attacking, so it runs a fixed receive chain (autocorr detector, full
%   CFO + channel estimate) and reports link quality: detection rate, SNR,
%   BER, and a LINK OK / JAMMING DETECTED banner driven by params.detect
%   thresholds against a baseline calibrated at start-up.
%
%   Run on the host wired to the B radio:  rx_B_console
%   Bring up A first (clean link), confirm LINK OK, then start C.
    add_paths_3node();
    params = load_parameters_3node();

    rx = init_n210_rx(params.B, params.rf);
    c  = onCleanup(@() safe_release(rx));
    run_rx_B(params, rx);
end

function safe_release(obj)
    try, release(obj); catch, end
end
