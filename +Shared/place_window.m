function pos = place_window(pos, extraTop, pointer, monitors)
% pos = Shared.place_window(pos, extraTop, pointer, monitors)
% Move a window position [x y w h] fully onto the monitor under the cursor.
%   extraTop  height above the content area besides the title bar,
%             e.g. a menu bar (default 0)
%   pointer   cursor location (default: current)
%   monitors  monitor rectangles, one per row (default: groot MonitorPositions)
% If the window is larger than the monitor, its top-left corner stays visible.

    TITLE_BAR = 32;
    if nargin < 2, extraTop = 0; end
    if nargin < 3, pointer = get(groot, 'PointerLocation'); end
    if nargin < 4, monitors = get(groot, 'MonitorPositions'); end

    % monitor under the cursor, otherwise the nearest one
    inside = pointer(1) >= monitors(:,1) & pointer(1) < monitors(:,1) + monitors(:,3) & ...
             pointer(2) >= monitors(:,2) & pointer(2) < monitors(:,2) + monitors(:,4);
    k = find(inside, 1);
    if isempty(k)
        centres = monitors(:,1:2) + monitors(:,3:4)/2;
        [~, k] = min(sum((centres - pointer(:)').^2, 2));
    end
    m = monitors(k,:);

    top = TITLE_BAR + extraTop;
    pos(1) = max(m(1), min(pos(1), m(1) + m(3) - pos(3)));
    pos(2) = min(m(2) + m(4) - pos(4) - top, max(pos(2), m(2)));
end
