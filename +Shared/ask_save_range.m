function [range, ok] = ask_save_range(fig, what)
% [range, ok] = Shared.ask_save_range(fig, what)
% Ask whether a module's Save writes the full length or only the current
% zoom window. Not used by Save session, which always saves everything.
%   what   shown in the title, e.g. 'Ephys'
%   range  [] for the full length, or [t1 t2] (s) for the zoom window
%   ok     false if cancelled

    data = Shared.SessionData.instance();
    zoom = data.currentZoom;
    answer = uiconfirm(fig, sprintf('Save the full length, or only the current zoom window (%.3f to %.3f s)?', ...
        zoom(1), zoom(2)), ['Save ' what], ...
        'Options', {'Full length', 'Zoom window', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
    ok = ~strcmp(answer, 'Cancel');
    range = [];
    if strcmp(answer, 'Zoom window'), range = zoom; end
end
