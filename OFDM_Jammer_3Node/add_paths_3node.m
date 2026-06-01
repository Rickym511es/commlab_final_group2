function add_paths_3node()
% add_paths_3node  Put the 3-node folder AND the reused 2-node code on path.
%   The 3-node project owns only the device/topology layer; all waveform and
%   attack logic (build_frame, gen_*, process_capture, detectors, modes/,
%   normalize_jammer, dashboard, load_parameters) is reused from the sibling
%   OFDM_Jammer_Project so the two never drift.
    here = fileparts(mfilename('fullpath'));
    addpath(genpath(here));                                   % 3-node code
    sibling = fullfile(here, '..', 'OFDM_Jammer_Project');
    if isfolder(sibling)
        addpath(genpath(sibling));                            % reused 2-node code
    else
        warning('add_paths_3node:sibling', ...
            'OFDM_Jammer_Project not found next to OFDM_Jammer_3Node (%s). Reused functions will be missing.', sibling);
    end
end
