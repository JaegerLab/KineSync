function hfig = KineSync(defaultPath)
% KineSync(defaultPath)
% Launcher with one button per module. It stays open while modules are
% used; running KineSync again brings it to the front (or reopens it).
% defaultPath: start folder of the file dialogs.

    data = Shared.SessionData.instance();
    if nargin >= 1
        data.defaultPath = defaultPath;
    elseif isempty(data.defaultPath)
        data.defaultPath = 'E:\Openfield\data';
    end
    if nargout == 1, hfig = []; end
    launcher = findall(groot, 'Type', 'figure', 'Tag', Shared.MenuBar.LauncherTag);
    if ~isempty(launcher)
        figure(launcher(1));
        if nargout == 1, hfig = launcher(1); end
        return;
    end

    fig = uifigure('Name', 'KineSync', 'Position', [100 100 400 200], ...
        'Tag', Shared.MenuBar.LauncherTag, 'CloseRequestFcn', @onLauncherClose);
    Shared.MenuBar(fig, {'Open', []; 'Save', []}, false);
    if nargout == 1, hfig = fig; end

    % Data Launcher Buttons
    grid1 = uigridlayout(fig, [2 2], 'Padding', [20 20 20 20]);
    for module = {'video', 'ephys', 'pose', 'behav'}
        uibutton(grid1, 'Text', Shared.module_name(module{1}), ...
            'ButtonPushedFcn', @(~,~)Shared.open_module(module{1}));
    end
end

% Closed by the user: with no module window open, end the session as Exit
% all does.
function onLauncherClose(src, ~)
    delete(src);
    if isempty(Shared.open_windows())
        delete(Shared.SessionData.instance());
    end
end
