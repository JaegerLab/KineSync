classdef MenuBar < handle
% Shared.MenuBar  Common File and Window menus of a KineSync window.
%
%   Shared.MenuBar(fig, fileItems, sessionEnabled)
%     fileItems       N-by-2 cell {label, callback} of the window's own File
%                     items, e.g. {'Open', @openVideo; 'Save', []}; an empty
%                     callback shows the item greyed out
%     sessionEnabled  false greys out Save session and Export to Workspace
%                     (default true)
%
%   File:   <fileItems> | Load session, Save session, Export to Workspace | Close, Exit all
%   Window: Ephys, Video, Pose, Behavior (open sub-windows listed below their module) | Open All, Bring All to Top
%
% Shortcuts: Ctrl+O Open, Ctrl+S Save, Ctrl+W Close, Ctrl+E Ephys, Ctrl+I Video,
% Ctrl+P Pose, Ctrl+B Behavior, Ctrl+A Open All, Ctrl+T Bring All to Top.
%
% The object lives as long as its window and rebuilds the Window menu on
% WindowsChanged. It does not need to be stored.

    properties (Constant)
        LauncherTag = 'KineSync launcher'
    end

    properties (Access = private)
        Figure
        WindowMenu
        Listener
    end

    methods
        function obj = MenuBar(fig, fileItems, sessionEnabled)
            if nargin < 3, sessionEnabled = true; end
            obj.Figure = fig;

            % headers padded with non-breaking spaces (plain ones are trimmed)
            % for wider headers; the Tag names the menu
            fileMenu = uimenu(fig, 'Text', ['File' repmat(char(160), 1, 6)], 'Tag', 'File');
            shortcuts = {'Open', 'O'; 'Open File', 'O'; 'Save', 'S'};
            for k = 1:size(fileItems, 1)
                callback = fileItems{k,2};
                item = uimenu(fileMenu, 'Text', fileItems{k,1}, 'Enable', onOff(~isempty(callback)));
                if ~isempty(callback), item.MenuSelectedFcn = callback; end
                key = shortcuts(strcmp(shortcuts(:,1), fileItems{k,1}), 2);
                if ~isempty(key), item.Accelerator = key{1}; end
            end
            uimenu(fileMenu, 'Text', 'Load session', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~)Shared.load_session(fig));
            uimenu(fileMenu, 'Text', 'Save session', 'Enable', onOff(sessionEnabled), ...
                'MenuSelectedFcn', @(~,~)Shared.save_session(fig));
            uimenu(fileMenu, 'Text', 'Export to Workspace', 'Enable', onOff(sessionEnabled), ...
                'MenuSelectedFcn', @(~,~)Shared.export2base(fig));
            uimenu(fileMenu, 'Text', 'Close', 'Separator', 'on', 'Accelerator', 'W', ...
                'MenuSelectedFcn', @(~,~)close(fig));
            uimenu(fileMenu, 'Text', 'Exit all', ...
                'MenuSelectedFcn', @(~,~)Shared.exit_all(true, fig));

            obj.WindowMenu = uimenu(fig, 'Text', ['Window' repmat(char(160), 1, 4)], 'Tag', 'Window');
            obj.rebuildWindowMenu();
            obj.Listener = listener(Shared.SessionData.instance(), 'WindowsChanged', ...
                @(~,~)obj.rebuildWindowMenu());
            addlistener(fig, 'ObjectBeingDestroyed', @(~,~)delete(obj));
        end

        function delete(obj)
            delete(obj.Listener);
        end
    end

    methods (Access = private)
        function rebuildWindowMenu(obj)
            if ~isgraphics(obj.WindowMenu), return; end
            delete(obj.WindowMenu.Children);
            windows = Shared.open_windows();
            modules = {'ephys', 'video', 'pose', 'behav'};
            keys    = {'E', 'I', 'P', 'B'};
            indent = repmat(char(160), 1, 4);   % plain spaces are trimmed
            for k = 1:numel(modules)
                module = modules{k};
                mine = windows(strcmp({windows.module}, module));
                uimenu(obj.WindowMenu, 'Text', Shared.module_name(module),'Checked', onOff(~isempty(mine)), ...
                    'Accelerator', keys{k}, 'MenuSelectedFcn', @(~,~)Shared.open_module(module));
                for sub = mine([mine.isSub])
                    uimenu(obj.WindowMenu, 'Text', [indent sub.fig.Name], 'Checked', 'on', ...
                        'MenuSelectedFcn', @(~,~)figure(sub.fig));
                end
            end
            uimenu(obj.WindowMenu, 'Text', 'Open All', 'Separator', 'on', 'Accelerator', 'A', ...
                'MenuSelectedFcn', @(~,~)openAll(modules));
            uimenu(obj.WindowMenu, 'Text', 'Bring All to Top', 'Accelerator', 'T', ...
                'MenuSelectedFcn', @(~,~)Shared.bring_all_to_front(obj.Figure));
        end
    end
end

% open every module window; open ones come to the front
function openAll(modules)
    for k = 1:numel(modules)
        Shared.open_module(modules{k});
    end
end

function value = onOff(tf)
    if tf
        value = 'on';
    else
        value = 'off';
    end
end
