function knob = apply_knob_overrides(knob, kv)
% apply_knob_overrides  Apply name-value overrides to a knob struct.
%   knob = apply_knob_overrides(knob, varargin_cell)
%
% Recognized keys (case-insensitive):
%   'bw_ratio'  -> knob.awgn_bw_ratio    (mode 9)
%   'freq'      -> knob.single_tone_freq (mode 10)
%   'freqs'     -> knob.multi_tone_freqs (mode 11)
%   'amps'      -> knob.multi_tone_amps  (mode 11)
%
% Unknown keys raise an error so typos are caught at the console.
    if isempty(kv), return; end
    if mod(numel(kv), 2) ~= 0
        error('apply_knob_overrides: name-value args must come in pairs.');
    end
    for i = 1:2:numel(kv)
        key = kv{i}; val = kv{i+1};
        if ~ischar(key) && ~isstring(key)
            error('apply_knob_overrides: override name #%d must be a string.', (i+1)/2);
        end
        switch lower(char(key))
            case 'bw_ratio'
                knob.awgn_bw_ratio    = val;
            case 'freq'
                knob.single_tone_freq = val;
            case 'freqs'
                knob.multi_tone_freqs = val(:).';
            case 'amps'
                knob.multi_tone_amps  = val(:).';
            otherwise
                error('apply_knob_overrides: unknown override "%s".', char(key));
        end
    end
end
