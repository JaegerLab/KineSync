function img = draw_markers(img, state, frameIdx, frameT, pxPerPoint)
% img = Video.draw_markers(img, state, frameIdx, frameT, pxPerPoint)
% Draw the video viewer's markers into one frame (pixel drawing, no GUI):
%   'o' event markers, alpha 2./(1+exp(|tEvent - tFrame|))
%   '+' committed pose marker on top (state.pose.x/y at frameIdx)
% Colors and line widths come from Shared.styles (magenta and cyan by default).
% Sizes follow the screen: markers 6 pt across, lines 2 pt wide.
%   img         H x W x 3 (or H x W, made RGB) frame
%   state       struct with pose ([] or x, y per frame) and events ([] or t, x, y)
%   pxPerPoint  video pixels per screen point (scale of the display)
% Coordinates are image pixels, as on the axes: x = column, y = row.

    if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end
    cls = class(img);
    peak = 1;
    if isinteger(img), peak = double(intmax(cls)); end
    out = double(img);

    style = Shared.styles();
    marker = 6 * pxPerPoint;           % diameter / width of the markers
    eventWidth = max(1, style.eventWidth * pxPerPoint);       % line widths
    poseWidth = max(1, style.poseMarkerWidth * pxPerPoint);

    if ~isempty(state.events) && ~isempty(state.events.t)
        alpha = 2 ./ (1 + exp(abs(state.events.t - frameT)));
        for k = 1:numel(state.events.t)
            out = blend(out, ringMask(size(out), state.events.x(k), state.events.y(k), marker/2, eventWidth), ...
                style.eventColor * peak, alpha(k));
        end
    end
    d = state.pose;
    if ~isempty(d) && frameIdx <= numel(d.x)
        out = blend(out, plusMask(size(out), d.x(frameIdx), d.y(frameIdx), marker/2, poseWidth), ...
            style.poseMarkerColor * peak, 1);
    end
    if peak > 1, out = round(out); end
    img = cast(out, cls);
end

function out = blend(out, mask, color, alpha)
    if isempty(mask) || ~any(mask.m(:)), return; end
    r = mask.rows; c = mask.cols;
    for ch = 1:3
        patch = out(r, c, ch);
        patch(mask.m) = (1 - alpha) * patch(mask.m) + alpha * color(ch);
        out(r, c, ch) = patch;
    end
end

% Pixels of a circle outline of radius r and line width w centred on (x, y).
function mask = ringMask(sz, x, y, r, w)
    mask = box(sz, x, y, r + w);
    if isempty(mask), return; end
    [cc, rr] = meshgrid(mask.cols, mask.rows);
    mask.m = abs(hypot(cc - x, rr - y) - r) <= w/2;
end

% Pixels of a '+' with arms of length a and line width w centred on (x, y).
function mask = plusMask(sz, x, y, a, w)
    mask = box(sz, x, y, a + w);
    if isempty(mask), return; end
    [cc, rr] = meshgrid(mask.cols, mask.rows);
    dx = abs(cc - x); dy = abs(rr - y);
    mask.m = (dx <= a & dy <= w/2) | (dy <= a & dx <= w/2);
end

% Bounding box of half-size h around (x, y), clipped to the image; [] if
% the point is missing or the box is off the image.
function mask = box(sz, x, y, h)
    mask = [];
    if ~isfinite(x) || ~isfinite(y), return; end
    rows = max(1, floor(y - h)):min(sz(1), ceil(y + h));
    cols = max(1, floor(x - h)):min(sz(2), ceil(x + h));
    if isempty(rows) || isempty(cols), return; end
    mask = struct('rows', rows, 'cols', cols, 'm', false(numel(rows), numel(cols)));
end
