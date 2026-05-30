function dash = make_dashboard()
% make_dashboard  Build the link-quality figure (status banner + 7 metric rows).
%   Rows: Frames detected, Detection rate, BER (recent), SNR (recent),
%         Baseline SNR, Throughput, CRC pass (recent).
    f = figure('Name','OFDM Link Monitor','Color','w','Position',[100 100 460 460]);
    ax = axes('Parent',f,'Position',[0 0 1 1]); axis(ax,[0 1 0 1]); axis(ax,'off');
    dash.statusBox = rectangle('Parent',ax,'Position',[0.06 0.80 0.88 0.14], ...
        'FaceColor',[0.85 0.65 0.1],'EdgeColor','none');
    dash.status = text(ax,0.5,0.87,'CALIBRATING...','FontSize',20, ...
        'FontWeight','bold','Color','w','HorizontalAlignment','center');
    labels = {'Frames detected','Detection rate','BER (recent)', ...
              'SNR (recent)','Baseline SNR','Throughput','CRC pass (recent)'};
    nrows  = numel(labels);
    dash.val = gobjects(1, nrows);
    for i = 1:nrows
        y = 0.70 - (i-1)*0.095;
        text(ax,0.10,y,labels{i},'FontSize',13,'Color',[0.3 0.3 0.3]);
        dash.val(i) = text(ax,0.92,y,'--','FontSize',14,'FontWeight','bold', ...
            'HorizontalAlignment','right','Color','k');
    end
    drawnow;
end
