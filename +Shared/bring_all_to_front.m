function bring_all_to_front(invokingFig)
% Shared.bring_all_to_front(invokingFig)
% Raise every open module window and sub-window; the invoking window last,
% so it ends up on top. The launcher is not raised, also when invoked
% from its Window menu.

    windows = Shared.open_windows();
    for k = 1:numel(windows)
        if nargin < 1 || ~isequal(windows(k).fig, invokingFig)
            figure(windows(k).fig);
        end
    end
    if nargin >= 1 && isgraphics(invokingFig, 'figure') && ...
            ~strcmp(invokingFig.Tag, Shared.MenuBar.LauncherTag)
        figure(invokingFig);
    end
end
