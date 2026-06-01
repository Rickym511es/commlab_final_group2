function tx_A_console()
% tx_A_console  Node A (USRP2) entry point: legitimate continuous OFDM TX.
%
%   The honest transmitter. Streams one fixed OFDM frame continuously on a
%   single N210 channel. A has NO knowledge of the jammer C - it just keeps
%   transmitting; B receives, C attacks from the outside.
%
%   Run on the host wired to the A radio:  tx_A_console
    add_paths_3node();
    params = load_parameters_3node();

    tx = init_n210_tx(params.A, params.rf);
    c  = onCleanup(@() safe_release(tx));
    run_tx_A(params, tx);
end

function safe_release(obj)
    try, release(obj); catch, end
end
