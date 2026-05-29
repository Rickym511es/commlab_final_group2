function out = mode_registry(action, params, pinnedMode)
% mode_registry  Single source of truth for the attack catalog and schedule.
%
%   modes = mode_registry()                       -> cell array of descriptors
%   modes = mode_registry('modes')                -> same as above
%   sched = mode_registry('schedule', params)     -> ordered schedule struct array
%   sched = mode_registry('schedule', params, m)  -> only mode id m's phases
%
% Each schedule entry: .mode (id), .type, .bw_idx, .label, .descriptor
% Replaces the old jam_tx make_schedule + jam_monitor phaseLabels/phaseModes,
% both of which had to be hand-kept in lockstep.

    if nargin < 1, action = 'modes'; end

    modes = {
        mode00_baseline()
        mode01_sts_sync()
        mode02_coarse_cfo()
        mode03_fine_cfo()
        mode04_pilot_cfo()
        mode05_chan_est()
        mode06_cp()
        mode07_flower()
        mode08_broadband()
        mode09_bandlimited_awgn()
        mode10_single_cw()
        mode11_multi_cw()
        mode12_fake_frame()
    };

    switch lower(action)
        case 'modes'
            out = modes;
        case 'schedule'
            if nargin < 3, pinnedMode = []; end
            out = build_schedule(modes, params, pinnedMode);
        otherwise
            error('mode_registry: unknown action "%s"', action);
    end
end

function sched = build_schedule(modes, params, pinnedMode)
    sb = params.sched;
    knob = params.knob;
    if sb.runBothTypes, allowed = [1 2]; else, allowed = sb.jamType; end

    typeName = containers.Map({0, 1, 2}, {'baseline', 'noise', 'struct'});
    typeKey  = @(t) typeName(t);

    sched = struct('mode', {}, 'type', {}, 'bw_idx', {}, 'label', {}, 'descriptor', {});

    for i = 1:numel(modes)
        m = modes{i};

        if ~isempty(pinnedMode) && m.id ~= pinnedMode && pinnedMode ~= -1
            continue;
        end

        if m.id == 0
            % baseline is a single phase regardless of allowed types
            sched(end+1) = make_phase(m, 0, 0, 'NO ATTACK (baseline)'); %#ok<AGROW>
            continue;
        end

        typesHere = intersect(m.types, allowed);
        for t = typesHere(:).'
            if isempty(m.sweep)
                bwList = 0;
            else
                bwList = 1:length(knob.(m.sweep));
            end
            for bw = bwList
                if bw > 0
                    lab = sprintf('%s (type=%d %s, %s=%.2f)', ...
                                  m.todo, t, typeKey(t), m.sweep, knob.(m.sweep)(bw));
                else
                    lab = sprintf('%s (type=%d %s)', m.todo, t, typeKey(t));
                end
                sched(end+1) = make_phase(m, t, bw, lab); %#ok<AGROW>
            end
        end
    end
end

function p = make_phase(m, t, bw, lab)
    p.mode       = m.id;
    p.type       = t;
    p.bw_idx     = bw;
    p.label      = lab;
    p.descriptor = m;
end
