function ax = plot_eta(result, target)
% Behav.plot_eta  Draw a Event-Triggered Average result into an axes.
%
%   ax = Behav.plot_eta(result)          – result from Behav.eta
%   ax = Behav.plot_eta(result, target)  – target is axes or figure handle
%
%   Draws:
%     • Raw ETA line (black solid)
%     • If there's control: dashed control-mean + shaded confidence interval
%     • Vertical centre line at t = 0
%     • Text labels at peak and trough times (relative to control mean)
%     • Legend
%
%   Normalization:
%     When result.zscore is true, display as pointwise z-score:
%       yDisp(t) = (y(t) - randomMean(t)) / randomStd(t)
%     This collapses the control mean to 0 and CI to ± nStd for every method.
%
% See also: Behav.eta

    %% ── Resolve target axes ──────────────────────────────────────────────
    if nargin < 2 || isempty(target) || isequal(target, false) || isequal(target, true)
        f  = figure();
        ax = axes(f);
    elseif isgraphics(target, 'axes')
        ax = target;
    elseif isgraphics(target, 'figure')
        ax = axes(target);
    else
        f  = figure();
        ax = axes(f);
    end

    %% ── Prepare display data (normalise if requested) ────────────────────
    t            = result.t(:);
    y            = result.y(:);
    randMean    = result.randomMean(:);
    randStd     = result.randomStd(:);
    nStd         = result.nStd;
    maxLag      = result.maxLag;
    doControl    = ~strcmp(result.method, 'none');

    zscore    = result.zscore && doControl;

    if zscore
        % Avoid divide-by-zero on flat std (should only happen if std==0 everywhere)
        safeStd = randStd;
        safeStd(safeStd == 0) = 1;

        yDisp         = (y - randMean) ./ safeStd;
        randMeanDisp = 0;           % collapses to 0
        randStdDisp  = 1;            % collapses to 1
    else
        yDisp         = y;
        randMeanDisp = randMean;
        randStdDisp  = randStd;
    end

    %% ── Draw ─────────────────────────────────────────────────────────────
    cla(ax);
    hold(ax, 'on');
    box(ax, 'off');

    % ── Control shading & mean (drawn first, so ETA renders on top) ──────
    if doControl
        ciUpper = randMeanDisp + nStd .* randStdDisp;
        ciLower = randMeanDisp - nStd .* randStdDisp;

        if zscore || isscalar(ciUpper) || isscalar(ciLower)
            % Flat rectangle to reduce complexity of the graph
            fillX = maxLag .* [-1 1 1 -1];
            fillY = [ciLower(1) ciLower(1) ciUpper(1) ciUpper(1)];
            fill1  = fill(ax, fillX, fillY, ...
                'k', 'EdgeColor', 'none', 'FaceAlpha', 0.15, ...
                'DisplayName', band_label(result.method,nStd));
            line1  = yline(ax, randMeanDisp(1), 'k--', ...
                'DisplayName', 'control mean');
        else
            % Curve-shaped fill
            fillX = [t; flipud(t)];
            fillY = [ciUpper; flipud(ciLower)];
            fill1  = fill(ax, fillX, fillY, ...
                'k', 'EdgeColor', 'none', 'FaceAlpha', 0.15, ...
                'DisplayName', band_label(result.method,nStd));
            line1  = plot(ax, t, randMeanDisp, 'k--', ...
                'DisplayName', 'control mean');
        end
        uistack(line1, 'down');
        uistack(fill1, 'bottom');
    end

    % ── ETA line ──────────────────────────────────────────────────────────
    plot(ax, t, yDisp, 'k', 'DisplayName', 'ETA');

    % ── Centre vertical line ──────────────────────────────────────────────
    xline(ax, 0, ':k', 'HandleVisibility', 'off');

    % ── Peak / trough text labels ─────────────────────────────────────────
    deviation = yDisp - randMeanDisp;

    [~, idxMax] = max(deviation);
    text(ax, t(idxMax), yDisp(idxMax), ...
        sprintf('%.3f s', t(idxMax)), ...
        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');

    [~, idxMin] = min(deviation);
    text(ax, t(idxMin), yDisp(idxMin), ...
        sprintf('%.3f s', t(idxMin)), ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'center');

    % ── Axis labels & legend ──────────────────────────────────────────────
    xlabel(ax, 't (s)');
    if zscore
        ylabel(ax, 'Amplitude (std)');
    else
        ylabel(ax, 'Amplitude');
    end

    if doControl
        legend(ax, 'Location', 'best');
    end

    hold(ax, 'off');
end

%% ── Helper: CI percentage for legend label ───────────────────────────────
function pct = ci_pct(n)
    % Approximate % of normal distribution within ±n sigma
    switch n
        case 1;  pct = 68.3;
        case 2;  pct = 95.5;
        case 3;  pct = 99.7;
        otherwise; pct = 100 * (erf(n/sqrt(2)));
    end
end

function label = band_label(method,nStd)
if strcmp(method,'global')
    label = sprintf('Approx. %g SEM band',nStd);
else
    label = sprintf('%g SD null band',nStd);
end
end
