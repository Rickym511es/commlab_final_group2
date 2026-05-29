function dash = make_dashboard()
% make_dashboard  Build the link-quality figure (status banner + 6 metric rows).
    f = figure('Name','OFDM Link Monitor','Color','w','Position',[100 100 460 420]);
    ax = axes('Parent',f,'Position',[0 0 1 1]); axis(ax,[0 1 0 1]); axis(ax,'off');
    dash.statusBox = rectangle('Parent',ax,'Position',[0.06 0.78 0.88 0.15], ...
        'FaceColor',[0.85 0.65 0.1],'EdgeColor','none');
    dash.status = text(ax,0.5,0.855,'CALIBRATING...','FontSize',20, ...
        'FontWeight','bold','Color','w','HorizontalAlignment','center');
    labels = {'Frames detected','Detection rate','BER (recent)', ...
              'SNR (recent)','Baseline SNR','Throughput'};
    dash.val = gobjects(1,6);
    for i = 1:6
        y = 0.66 - (i-1)*0.105;
        text(ax,0.10,y,labels{i},'FontSize',13,'Color',[0.3 0.3 0.3]);
        dash.val(i) = text(ax,0.92,y,'--','FontSize',14,'FontWeight','bold', ...
            'HorizontalAlignment','right','Color','k');
    end
    drawnow;
end
