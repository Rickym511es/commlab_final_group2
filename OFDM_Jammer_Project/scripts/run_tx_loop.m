function run_tx_loop(params, sched, tx)
% run_tx_loop  TX while-loop. For each scheduled phase, build the jammer
% from the mode's descriptor, RMS-normalize, joint-clip-protect, and
% continuously stream [real_frame, jammer] to the B210 until the schedule
% completes.

    spec = params.spec;
    [real_frame, info, ~] = build_frame(spec);
    tx_rms = rms(real_frame);

    numPhases = numel(sched);
    totalSec  = numPhases * params.sched.secondsPerPhase;
    fprintf('\nSchedule: %d phases x %d s = %d s total\n', ...
            numPhases, params.sched.secondsPerPhase, totalSec);
    for i = 1:numPhases
        fprintf('  [%2d] %3d-%3ds : %s\n', i, ...
                (i-1)*params.sched.secondsPerPhase, ...
                i*params.sched.secondsPerPhase, sched(i).label);
    end

    ts = []; cd_jam = [];
    if params.tx.liveDisplay
        ts = timescope('SampleRate', params.tx.fs, ...
            'TimeSpanSource','property','TimeSpan', length(real_frame)/params.tx.fs, ...
            'Title','TX Time Domain: ch1 real / ch2 jammer', ...
            'ChannelNames',{'ch1 real (Re)','ch2 jammer (Re)'}, ...
            'AxesScaling','Auto');
        cd_jam = comm.ConstellationDiagram( ...
            'Title','TX Jammer Constellation (TODO8 -> flower)', ...
            'ShowReferenceConstellation',false, ...
            'XLimits',[-2 2],'YLimits',[-2 2]);
    end
    c = onCleanup(@() tx_cleanup(ts, cd_jam));

    fprintf('\nStarting transmission (%d s).\n\n', totalSec);
    t0 = tic; iter = 0; curPhase = 0; consecErr = 0; underrunCnt = 0;
    txMat = [real_frame, zeros(size(real_frame))];

    while toc(t0) < totalSec
        elapsed = toc(t0);
        p = min(numPhases, floor(elapsed / params.sched.secondsPerPhase) + 1);
        if p ~= curPhase
            curPhase = p;
            s = sched(p);
            jammer = s.descriptor.build(s.type, s.bw_idx, real_frame, info, ...
                                         params.tx.fs, params.knob);
            if s.type ~= 0
                jammer = normalize_jammer(jammer, real_frame, s.type, params.knob);
            end
            jpk = max(abs(jammer));
            if jpk > 0.95
                jammer = jammer * (0.95 / jpk);
                fprintf('  (jammer peak %.2f > 0.95, scaling)\n', jpk);
            end
            txMat = [real_frame, jammer];
            fprintf('[%6.1fs] >>> phase %d/%d: %s | jam_rms/tx_rms=%.2f\n', ...
                    elapsed, p, numPhases, s.label, rms(jammer)/max(tx_rms,1e-12));
            if params.tx.liveDisplay
                ts([real(txMat(:,1)), real(txMat(:,2))]);
                feed_jam_const(cd_jam, jammer, info);
            end
        end

        iter = iter + 1;
        try
            underrun = tx(txMat);  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            fprintf('[%6.1fs] tx exception (#%d): %s\n', ...
                    toc(t0), consecErr, ME.message);
            if consecErr == 5, try, release(tx); catch, end, end
            if consecErr >= 10
                error('10 consecutive tx failures, check USB/connection. Last: %s', ME.message);
            end
            pause(0.1);
            continue;
        end
        if underrun, underrunCnt = underrunCnt + 1; end

        if params.tx.liveDisplay && mod(iter, params.tx.displayEvery) == 0
            ts([real(txMat(:,1)), real(txMat(:,2))]);
            feed_jam_const(cd_jam, txMat(:,2), info);
        end
    end
    fprintf('\nTransmission complete. Frames sent=%d, underruns=%d.\n', iter, underrunCnt);
end

function tx_cleanup(ts, cd_jam)
    if ~isempty(ts),     try, release(ts);     catch, end, end
    if ~isempty(cd_jam), try, release(cd_jam); catch, end, end
end
