function [target_time, info] = convert_time(source_time, source_anchor, target_anchor, varargin)
% Convert times from one clock to another using matched anchor points.
%
%   [target_time, info] = Shared.convert_time(source_time, source_anchor, target_anchor)
%   [...] = Shared.convert_time(..., 'Method', 'linear', 'MaxResidual', 1e-3, 'Offset', 0)
%
% Each anchor is one moment known on both clocks: source_anchor(k) and
% target_anchor(k). For example, video frame numbers and the ephys times
% of their camera TTLs, or Bpod camera pulse times and the same pulses
% recorded by Open Ephys.
%
% Inputs
%   source_time   : values to convert, on the source clock (any size)
%   source_anchor : anchors on the source clock, strictly increasing
%   target_anchor : the same anchors on the target clock, strictly
%                   increasing; same count as source_anchor (at least 2)
%
% Options
%   'Method'      : between the first and last anchor:
%                   'linear' (default) interpolates between neighbouring
%                   anchors, so an anchor converts exactly to its partner;
%                   'pchip', 'makima' or 'spline' interpolate smoothly;
%                   'fit' uses the straight-line fit everywhere.
%                   Outside the anchors, times always follow the slope of the
%                   straight-line fit, continued from the first or last anchor
%                   (with 'fit', the fitted line itself).
%   'MaxResidual' : largest acceptable distance of an anchor from the
%                   straight-line fit (target units), default 1e-3. A
%                   larger one gives warning KineSync:convert_time:residual.
%   'Offset'      : constant added after converting (target units), default 0
%
% Outputs
%   target_time : source_time on the target clock, same size
%   info        : slope, offset (target = slope*source + offset),
%                 driftPpm (slope-1 in ppm, meaningful when both clocks
%                 count seconds), residualRms, residualMax, nAnchors,
%                 residuals
%
% Example (wheel times from Bpod to Open Ephys)
%   load(bpodFile, 'SessionData');
%   ttlB = bpod_camera_ttl(SessionData);         % tools folder
%   W = SessionData.WheelData;
%   W.Times = Shared.convert_time(W.Times, ttlB, ttlEphys);

    p = inputParser;
    p.addParameter('Method', 'linear', @(s) any(strcmpi(s, {'linear', 'pchip', 'makima', 'spline', 'fit'})));
    p.addParameter('MaxResidual', 1e-3, @(v) isscalar(v) && v > 0);
    p.addParameter('Offset', 0, @(v) isscalar(v) && isfinite(v));
    p.parse(varargin{:});
    opt = p.Results;
    method = lower(opt.Method);

    sa = double(source_anchor(:));
    ta = double(target_anchor(:));
    if numel(sa) ~= numel(ta)
        error('KineSync:convert_time:count', ...
            'Anchor counts differ: %d source and %d target anchors.', numel(sa), numel(ta));
    end
    if numel(sa) < 2
        error('KineSync:convert_time:count', 'At least two anchors are required.');
    end
    if ~all(isfinite(sa)) || ~all(isfinite(ta))
        error('KineSync:convert_time:anchors', 'Anchors must be finite.');
    end
    if any(diff(sa) <= 0) || any(diff(ta) <= 0)
        error('KineSync:convert_time:anchors', 'Anchors must be strictly increasing.');
    end

    %% Straight-line fit and residual check
    coef = polyfit(sa, ta, 1);
    residuals = ta - polyval(coef, sa);
    info.slope       = coef(1);
    info.offset      = coef(2);
    info.driftPpm    = (coef(1) - 1) * 1e6;
    info.residualRms = sqrt(mean(residuals.^2));
    info.residualMax = max(abs(residuals));
    info.nAnchors    = numel(sa);
    info.residuals   = residuals;
    if info.residualMax > opt.MaxResidual
        warning('KineSync:convert_time:residual', ...
            ['An anchor is %.3g from the straight-line fit (limit %.3g). Anchors may ' ...
            'be missing or extra on one clock, or the wrong channel was used.'], ...
            info.residualMax, opt.MaxResidual);
    end

    %% Convert
    x = double(source_time);
    if strcmp(method, 'fit')
        target_time = polyval(coef, x);
    else
        target_time = zeros(size(x));
        before = x < sa(1);
        after = x > sa(end);
        inside = ~before & ~after;
        target_time(inside) = interp1(sa, ta, x(inside), method);
        target_time(before) = ta(1) + coef(1) * (x(before) - sa(1));
        target_time(after) = ta(end) + coef(1) * (x(after) - sa(end));
        target_time(isnan(x)) = NaN;
    end
    target_time = target_time + opt.Offset;
end
