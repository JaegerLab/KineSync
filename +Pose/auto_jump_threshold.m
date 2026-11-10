function [thr, info] = auto_jump_threshold(x, y, varargin)
%AUTO_JUMP_THRESHOLD  Data-driven jump threshold for DeepLabCut trajectories.
%
%   thr = Pose.auto_jump_threshold(x, y) returns a frame-to-frame displacement
%   threshold (pixels) separating normal movement from tracking errors,
%   estimated from the histogram of log10(displacement).
%
%   Rationale: plotted on a log axis, frame-to-frame displacement is
%   usually bimodal. Normal movement forms a large mode at a few pixels;
%   mislabels (a point jumping to another body part, the other mouse, or
%   the arena edge) form a smaller mode at tens to hundreds of pixels.
%   The threshold is placed in the valley between them.
%
%   [thr, info] = Pose.auto_jump_threshold(x, y, Name, Value, ...)
%
%   Options
%     'Method'      'valley' (default) | 'gmm' | 'mad'
%                   valley : minimum of the smoothed log-histogram between
%                            the main mode and the error mode. No toolbox.
%                   gmm    : 2-component Gaussian mixture on log10(d);
%                            threshold where posteriors are equal.
%                            Needs Statistics and ML Toolbox.
%                   mad    : median + K * robust SD in log space. No toolbox.
%                            Works even when there is no visible error mode.
%     'NBins'       number of histogram bins in log space (default 150)
%     'SmoothSigma' Gaussian smoothing of the histogram, in bins (default 2)
%     'ValleyRatio' valley must be below this fraction of the error-mode
%                   peak height to count as a real valley (default 0.5)
%     'MinErrorFrac' error mode must hold at least this fraction of
%                   samples to count (default 0.001)
%     'MadK'        K for the MAD method / fallback (default 4)
%     'Plot'        true to show the histogram and thresholds (default false)
%
%   info fields
%     thrValley, thrMad, thrGmm  (pixels; NaN if not computed)
%     methodUsed   method actually used (valley falls back to mad when no
%                   second mode is found, e.g. a very clean video)
%     fracAbove    fraction of frame pairs above thr
%     d             displacement vector used (pixels)
%
%   Example (one body part)
%     [thr, info] = auto_jump_threshold(x, y, 'Plot', true);
%     jumps = find(hypot(diff(x), diff(y)) > thr);

p = inputParser;
addParameter(p, 'Method', 'valley');
addParameter(p, 'NBins', 150);
addParameter(p, 'SmoothSigma', 2);
addParameter(p, 'ValleyRatio', 0.5);
addParameter(p, 'MinErrorFrac', 0.001);
addParameter(p, 'MadK', 4);
addParameter(p, 'Plot', false);
parse(p, varargin{:});
o = p.Results;
method = lower(o.Method);

x = x(:); y = y(:);
d = hypot(diff(x), diff(y));
ok = isfinite(d) & d > 0;          % log needs d > 0; drop NaN frames
ld = log10(d(ok));
if numel(ld) < 50
    error('auto_jump_threshold:tooFewSamples', ...
        'Need at least 50 valid displacements, got %d.', numel(ld));
end

% ---- histogram in log space, smoothed ---------------------------------
edges   = linspace(min(ld), max(ld), o.NBins + 1);
counts  = histcounts(ld, edges);
centers = (edges(1:end-1) + edges(2:end)) / 2;
cs      = gauss_smooth(counts, o.SmoothSigma);

info = struct('thrValley', NaN, 'thrMad', NaN, ...
              'thrGmm', NaN, 'methodUsed', method, 'fracAbove', NaN, ...
              'd', d);

% ---- MAD (always computed: it is the fallback) ------------------------
med = median(ld);
rsd = 1.4826 * median(abs(ld - med));
info.thrMad = 10^(med + o.MadK * rsd);

% ---- valley between main mode and error mode --------------------------
info.thrValley = valley_threshold(cs, centers, numel(ld), o);

% ---- Gaussian mixture (optional, needs toolbox) -----------------------
if strcmp(method, 'gmm') || o.Plot
    info.thrGmm = gmm_threshold(ld);
end

% ---- choose -----------------------------------------------------------
switch method
    case 'valley'
        thr = info.thrValley;
        if isnan(thr)
            thr = info.thrMad;
            info.methodUsed = 'mad (valley fallback: no error mode found)';
        end
    case 'gmm'
        thr = info.thrGmm;
        if isnan(thr)
            thr = info.thrMad;
            info.methodUsed = 'mad (gmm fallback)';
        end
    case 'mad'
        thr = info.thrMad;
    otherwise
        error('auto_jump_threshold:badMethod', 'Unknown method "%s".', o.Method);
end
info.fracAbove = mean(d(isfinite(d)) > thr);

if o.Plot
    plot_hist(ld, edges, counts, cs, info, thr);
end
end

% =======================================================================
function thrPix = valley_threshold(cs, centers, nTotal, o)
% Find the most distinct secondary peak to the right of the main mode and
% return the minimum of the smoothed histogram between the two.
thrPix = NaN;
n = numel(cs);
[~, iMain] = max(cs);
bestRatio = Inf;
for j = iMain+2 : n
    isPeak = cs(j) > cs(j-1) && (j == n || cs(j) >= cs(j+1));
    if ~isPeak, continue; end
    [vmin, iv] = min(cs(iMain:j));
    ratio = vmin / cs(j);
    % mass of the candidate error mode = everything right of the valley
    massRight = sum(cs(iMain+iv-1:end)) / sum(cs);
    if ratio < o.ValleyRatio && massRight >= o.MinErrorFrac && ...
            massRight * nTotal >= 5 && ratio < bestRatio
        bestRatio = ratio;
        thrPix = 10^centers(iMain + iv - 1);
    end
end
end

% =======================================================================
function thrPix = gmm_threshold(ld)
thrPix = NaN;
if exist('fitgmdist', 'file') ~= 2
    return;
end
try
    gm = fitgmdist(ld(:), 2, 'Replicates', 5, ...
        'Options', statset('MaxIter', 500));
    [mus, ord] = sort(gm.mu);
    grid = linspace(mus(1), mus(2), 500)';
    post = posterior(gm, grid);
    pHigh = post(:, ord(2));
    k = find(pHigh >= 0.5, 1, 'first');
    if ~isempty(k)
        thrPix = 10^grid(k);
    end
catch
    % fit failed (e.g. unimodal data) -> leave NaN, caller falls back
end
end

% =======================================================================
function y = gauss_smooth(v, sigma)
if sigma <= 0, y = v; return; end
h = ceil(3 * sigma);
g = exp(-(-h:h).^2 / (2 * sigma^2));
g = g / sum(g);
y = conv(v, g, 'same');
end

% =======================================================================
function plot_hist(ld, edges, counts, cs, info, thr)
figure('Color', 'w');
centers = (edges(1:end-1) + edges(2:end)) / 2;
bar(centers, counts, 1, 'FaceColor', [0.75 0.75 0.75], 'EdgeColor', 'none');
hold on;
plot(centers, cs, 'k', 'LineWidth', 1.5);
set(gca, 'YScale', 'log');
yl = ylim;
names = {'thrValley', 'thrMad', 'thrGmm'};
cols  = [0.85 0.2 0.2; 0.3 0.7 0.3; 0.6 0.3 0.7];
h = []; lab = {};
for i = 1:numel(names)
    v = info.(names{i});
    if ~isnan(v)
        h(end+1) = plot(log10([v v]), yl, '--', 'Color', cols(i,:), ...
            'LineWidth', 1.5); %#ok<AGROW>
        lab{end+1} = sprintf('%s = %.1f px', strrep(names{i}, '_', '\_'), v); %#ok<AGROW>
    end
end
plot(log10([thr thr]), yl, 'k-', 'LineWidth', 2);
xlabel('log_{10} frame-to-frame displacement (px)');
ylabel('count (log scale)');
title(sprintf('Chosen: %.1f px (%s), %.2f%% of frames above', thr, ...
    strrep(info.methodUsed, '_', '\_'), 100 * info.fracAbove));
legend(h, lab, 'Location', 'northeast');
end
