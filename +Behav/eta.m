function result = eta(signal, signalT, eventTime, varargin)
% Behav.eta  Event-Triggered Average
%
%   result = Behav.eta(signal, signalT, eventTime, Name, Value, ...)
%
%   Required inputs:
%     signal        : ephys signal vector
%     signalT      : Time axis of signal (seconds)
%     eventTime : Array of event times (seconds)
%
%   Name-Value parameters:
%     'maxLag'   - Window half-width in seconds          (default: 0.5)
%     'method'    - Control method: 'dither' | 'random_time' |
%                   'isi_shuffle' | 'global' | 'none'     (default: 'dither')
%     'nRep'      - Repetitions for repeated methods      (default: 100)
%     'offset'    - Dither within [-offset, offset) sec   (default: 1)
%     'zscore'    - Store zscore flag (plot-time only)    (default: false)
%     'nStd'      - CI width in std devs                  (default: 3)
%     'plot'      - false / true / axes / figure handle   (default: false)
%
%   Output: flat struct with fields:
%     t, y, maxLag, method, nRep, offset, zscore, nStd,
%     randomT, randomMean, randomStd, eventNum, sampleRate

    %% ── Parse name-value arguments ───────────────────────────────────────
    p = inputParser();
    p.addRequired('ephys');
    p.addRequired('signalT');
    p.addRequired('eventTime');
    p.addParameter('maxLag',   0.5,      @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('method',    'dither', @(x) ischar(x) || isstring(x));
    p.addParameter('nRep',      100,      @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('offset',    1,        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('zscore',    false,    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('nStd',      3,        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('plot',      false);
    p.parse(signal, signalT, eventTime, varargin{:});

    maxLag   = p.Results.maxLag;
    
    method    = char(p.Results.method);
    doControl = ~strcmp(method, 'none');
    nRep      = round(p.Results.nRep);
    offset    = p.Results.offset;
    zscore = logical(p.Results.zscore);
    nStd      = p.Results.nStd;
    plotArg   = p.Results.plot;

    % Validate method string
    validMethods = {'none','global','random_time','isi_shuffle','dither'};
    if ~ismember(method, validMethods)
        error('behav:eta:badMethod', ...
            'method must be one of: none, global, dither, random_time, isi_shuffle. Got: %s', method);
    end

    %% ── Pre-process signals ──────────────────────────────────────────────
    validateattributes(signal, {'numeric'}, {'vector','real','nonempty'});
    if ~any(isfinite(signal)), error('behav:eta:signal', 'The signal has no finite samples.'); end
    signal       = signal(:);
    signal(~isfinite(signal)) = NaN;
    signalT     = signalT(:);
    eventTime = eventTime(:);

    validateattributes(signalT, {'numeric'}, {'vector','real','finite','increasing'});
    if numel(signalT) ~= numel(signal) || numel(signalT) < 2
        error('behav:eta:timebase', 'Signal and time must have the same length (at least 2).');
    end
    dt = median(diff(signalT));
    if any(abs(diff(signalT)-dt) > max(1e-9, dt*1e-3))
        error('behav:eta:timebase', 'ETA requires a regularly sampled signal without timestamp gaps.');
    end
    sampleRate = 1/dt;
    traceLength = numel(signal);
    maxLag = min(maxLag, signalT(end)-signalT(1));
    eventTime = sort(eventTime(isfinite(eventTime)));
    keep = eventTime >= signalT(1) & eventTime <= signalT(end);
    if any(~keep)
        warning('behav:eta:outOfBound', 'Some event times were out of bounds and removed.');
    end
    eventTime = eventTime(keep);
    eventIndex = round((eventTime-signalT(1))*sampleRate)+1;
    eventNum = numel(eventIndex);
    if eventNum == 0
        error('behav:eta:noEvents', 'No event times fall within the ephys recording.');
    end
    nRep = max(1, nRep);
    lagSamps = round(maxLag*sampleRate);
    t = (-lagSamps:lagSamps)'/sampleRate;
    tic
    [yRaw, sampleCount] = event_average(signal, eventIndex, lagSamps);
    elapsedT = toc;

    %% ── Long-computation warning ─────────────────────────────────────────
    % Only relevant for repeated-method controls
    needsRep = doControl && ~strcmp(method, 'global');
    actualMethod = method;   % may be overridden to 'global' if user cancels

    if needsRep
        estimatedTotal = elapsedT * nRep;
        if estimatedTotal > 5
            msg = sprintf( ...
                ['Estimated computation time: %.1f seconds\n' ...
                 '(%d repetitions × %.2f s each)\n\n' ...
                 'Continue with ''%s''?\n' ...
                 'Or use the fast ''global'' control instead?'], ...
                estimatedTotal, nRep, elapsedT, method);
            choice = questdlg(msg, 'Long Computation Warning', ...
                'Continue', 'Use Global', 'No Control', 'Continue');
            switch choice
                case 'No Control'
                    % Return minimal result with no control
                    actualMethod = 'none';  
                    doControl = false;
                case 'Use Global'
                    actualMethod = 'global';
                    % needsRep     = false;
                    % fall through to control computation below
                % 'Continue' → proceed as requested
            end
        end
    end

    %% ── Random control ───────────────────────────────────────────────────
    randomMean = zeros(size(t));
    randomStd  = zeros(size(t));

    if doControl
        switch actualMethod
            %% ── global: whole-trace mean/std, no lag structure ───────────
            case 'global'
                randomMean = mean(signal, 'omitnan')*ones(size(t));
                randomStd = std(signal, 'omitnan')./sqrt(sampleCount);
                randomStd(sampleCount==0) = NaN;

            %% ── dither: jitter each real event by ±offset seconds ────────
            case 'dither'
                randomEta = zeros(2 * lagSamps + 1, nRep);
                for k = 1:nRep
                    randShift = round(offset * 2 * sampleRate .* (rand(size(eventIndex)) - 0.5));
                    randIdx   = eventIndex + randShift;
                    randIdx(randIdx > traceLength | randIdx <= 0) = [];
                    randomEta(:, k) = event_average(signal, randIdx, lagSamps);
                end
                randomMean = mean(randomEta, 2, 'omitnan');
                randomStd  = std(randomEta, 0, 2, 'omitnan');

            %% ── random_time: draw eventNum times uniformly ───────────────
            case 'random_time'
                randomEta = zeros(2 * lagSamps + 1, nRep);
                for k = 1:nRep
                    if eventNum <= traceLength
                        randIdx = randperm(traceLength, eventNum);
                    else
                        randIdx = randi(traceLength, eventNum, 1);
                    end
                    randomEta(:, k) = event_average(signal, randIdx, lagSamps);
                end
                randomMean = mean(randomEta, 2, 'omitnan');
                randomStd  = std(randomEta, 0, 2, 'omitnan');

            %% ── isi_shuffle: permute inter-event intervals ────────────────
            case 'isi_shuffle'
                isi = diff([signalT(1); eventTime]);
                randomEta = zeros(2 * lagSamps + 1, nRep);
                for k = 1:nRep
                    shuffledIsi  = isi(randperm(length(isi)));
                    randTimes = signalT(1) + cumsum(shuffledIsi);
                    randIdx = round((randTimes-signalT(1))*sampleRate)+1;
                    randIdx(randIdx > traceLength | randIdx <= 0) = [];
                    randomEta(:, k) = event_average(signal, randIdx, lagSamps);
                end
                randomMean = mean(randomEta, 2, 'omitnan');
                randomStd  = std(randomEta, 0, 2, 'omitnan');
        end
    end

    %% ── Build output struct ──────────────────────────────────────────────
    result = struct();
    result.t           = t;
    result.y           = yRaw;
    result.maxLag     = maxLag;
    result.method      = actualMethod;   % what was actually computed
    result.nRep        = nRep;
    result.offset      = offset;
    result.zscore      = zscore;
    result.nStd        = nStd;
    result.randomT    = t;
    result.randomMean = randomMean;
    result.randomStd  = randomStd;
    result.eventNum    = eventNum;
    result.sampleRate = sampleRate;
    result.sampleCount = sampleCount;

    %% ── Optional plot ────────────────────────────────────────────────────
    if ~isequal(plotArg, false) && ~isequal(plotArg, 0)
        Behav.plot_eta(result, plotArg);
    end
end

function [y, counts] = event_average(signal, indices, maxlag)
% Accumulate duplicate events; each lag uses only observed finite samples.
N = numel(signal);
if isempty(indices), y = nan(2*maxlag+1,1); counts = zeros(size(y)); return; end
train = accumarray(indices(:), 1, [N 1]);
valid = isfinite(signal);
signal(~valid) = 0;
numerator = xcorr(signal, train, maxlag);
counts = round(xcorr(double(valid), train, maxlag));
y = nan(size(numerator));
keep = counts > 0;
y(keep) = numerator(keep)./counts(keep);
end
