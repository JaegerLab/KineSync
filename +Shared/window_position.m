function pos = window_position(module, default, monitors)
% pos = Shared.window_position(module, default, monitors)
% Position for a new module window: where it was last closed, kept in the
% MATLAB preferences (see Shared.remember_position), otherwise default.
%   monitors  monitor rectangles, one per row (default: groot MonitorPositions)
% A saved window whose centre is off every monitor, e.g. one left on a screen
% that is no longer connected, is moved onto the nearest monitor.

    MENU_BAR = 22;
    if nargin < 3, monitors = get(groot, 'MonitorPositions'); end

    pos = default;
    if ~ispref('KineSync', 'windowPositions'), return; end
    saved = getpref('KineSync', 'windowPositions');
    if ~isstruct(saved) || ~isfield(saved, module), return; end
    p = saved.(module);
    if ~isnumeric(p) || numel(p) ~= 4 || any(~isfinite(p)) || any(p(3:4) <= 0), return; end

    pos = double(p(:)');
    centre = pos(1:2) + pos(3:4)/2;
    onScreen = centre(1) >= monitors(:,1) & centre(1) < monitors(:,1) + monitors(:,3) & ...
               centre(2) >= monitors(:,2) & centre(2) < monitors(:,2) + monitors(:,4);
    if ~any(onScreen)
        pos = Shared.place_window(pos, MENU_BAR, centre, monitors);
    end
end
