function run_tx_A(params, tx)
% run_tx_A  Node A TX loop: stream one fixed OFDM frame continuously on a
% single channel until the user stops it (Ctrl-C). Mirrors the streaming /
% underrun / error handling of the 2-node run_tx_loop, minus the per-phase
% schedule, jammer build, dual-channel matrix and jammer displays.

    rf = params.rf;
    [real_frame, ~, ~] = build_frame(rf.spec);    % reused builder
    txMat = real_frame;                            % single channel

    ts = [];
    if params.A.liveDisplay
        ts = timescope('SampleRate', rf.fs, ...
            'TimeSpanSource','property','TimeSpan', length(real_frame)/rf.fs, ...
            'Title','Node A TX Time Domain (real OFDM frame)', ...
            'ChannelNames',{'In-phase (I)'}, 'AxesScaling','Auto');
    end
    c = onCleanup(@() a_cleanup(ts));

    fprintf('\nNode A transmitting continuously. Press Ctrl-C to stop.\n');
    fprintf('frame length = %d samples (%.2f ms)\n\n', ...
            length(real_frame), 1e3*length(real_frame)/rf.fs);

    iter = 0; underrunCnt = 0; consecErr = 0; t0 = tic;
    while true
        iter = iter + 1;
        try
            underrun = tx(txMat);  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            fprintf('[%6.1fs] A tx exception (#%d): %s\n', toc(t0), consecErr, ME.message);
            if consecErr == 5, try, release(tx); catch, end, end
            if consecErr >= 10
                error('10 consecutive tx failures on node A. Last: %s', ME.message);
            end
            pause(0.1); continue;
        end
        if underrun, underrunCnt = underrunCnt + 1; end

        if params.A.liveDisplay && mod(iter, params.A.displayEvery) == 0
            ts(real(txMat));
        end
        if mod(iter, 2000) == 0
            fprintf('[%6.1fs] A frames sent=%d, underruns=%d\n', ...
                    toc(t0), iter, underrunCnt);
        end
    end
end

function a_cleanup(ts)
    if ~isempty(ts), try, release(ts); catch, end, end
end
