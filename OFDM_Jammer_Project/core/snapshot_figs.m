function folder = snapshot_figs(prefix, baseDir)
% snapshot_figs  Save every open figure (uifigure, timescope, spectrum,
% constellation, dashboard...) as a PNG into a timestamped folder.
%
%   folder = snapshot_figs()              - prefix='', baseDir=pwd
%   folder = snapshot_figs(prefix)        - filenames start with prefix
%   folder = snapshot_figs(prefix, dir)   - put folder under dir
%
% Returns the absolute path of the folder created.
%
% exportgraphics is tried first (modern, handles uifigure/uiaxes); falls
% back to print for older System Object UIs that don't accept it.

    if nargin < 1, prefix = ''; end
    if nargin < 2, baseDir = pwd; end

    stamp  = datestr(now, 'yyyymmdd_HHMMSS');
    folder = fullfile(baseDir, sprintf('snapshots_%s', stamp));
    if ~exist(folder, 'dir'), mkdir(folder); end

    figs = findall(groot, 'Type', 'figure');
    saved = 0;
    for k = 1:numel(figs)
        f = figs(k);
        nm = matlab.lang.makeValidName(char(f.Name));
        if isempty(nm), nm = sprintf('fig_%d', k); end
        if isempty(prefix)
            fname = fullfile(folder, [nm '.png']);
        else
            fname = fullfile(folder, sprintf('%s_%s.png', prefix, nm));
        end
        ok = false;
        try
            exportgraphics(f, fname);
            ok = true;
        catch
            try, print(f, fname, '-dpng', '-r150'); ok = true; catch, end
        end
        if ok, saved = saved + 1;
        else,  fprintf(2, 'snapshot failed for "%s"\n', f.Name); end
    end
    fprintf('Saved %d figure(s) to %s\n', saved, folder);
end
