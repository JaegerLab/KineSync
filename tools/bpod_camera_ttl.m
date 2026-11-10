function [ttl, info] = bpod_camera_ttl(SessionData, varargin)
% Rebuild camera trigger times from a Bpod session file.
%
%   ttl = bpod_camera_ttl(SessionData)
%   [ttl, info] = bpod_camera_ttl(SessionData, 'TimerID', 1, 'StopState', 'TimerEnd')
%
% The camera trigger is a looping Bpod global timer. With its events
% turned off ('SendEvents',0), Bpod logs only the first GlobalTimerN_Start
% of each trial, not the pulses. The loop runs on the state machine clock,
% so pulse k of a trial rises at
%     TrialStartTimestamp + GlobalTimerN_Start(1) + k * TTLPeriod
% until the timer is cancelled (entry of StopState) or the trial ends.
% If the timer's events were on, the logged GlobalTimerN_Start times are
% used as they are.
%
% Inputs
%   SessionData : Bpod session data (load(bpodFile, 'SessionData'))
%
% Options
%   'TimerID'   : global timer driving the camera, default 1
%   'StopState' : state that cancels the timer, default 'TimerEnd'. If a
%                 trial has no such state, or did not enter it, the
%                 trial end is used (Bpod clears all timers at trial end).
%   'Period'    : pulse period (s), onset to onset. Default: each trial's
%                 TrialSettings(i).GUI.TTLPeriod
%
% Outputs
%   ttl  : rising-edge times of all trials in one column vector, on the
%          Bpod session clock (s), the same clock as TrialStartTimestamp
%   info : per-trial table with Trial, Start, Stop, Period, nPulses, Source
%          ('rebuilt', 'logged' or 'none' for trials without the timer)
%
% Example
%   load(bpodFile, 'SessionData');
%   ttlB = bpod_camera_ttl(SessionData);
%   W.Times = Shared.convert_time(W.Times, ttlB, ttlEphys);

    p = inputParser;
    p.addParameter('TimerID', 1, @(v) isscalar(v) && v >= 1);
    p.addParameter('StopState', 'TimerEnd', @(s) ischar(s) || isstring(s));
    p.addParameter('Period', [], @(v) isempty(v) || (isscalar(v) && v > 0));
    p.parse(varargin{:});
    opt = p.Results;

    startEvent = sprintf('GlobalTimer%d_Start', opt.TimerID);
    nTrials = SessionData.nTrials;

    perTrial = cell(nTrials, 1);
    Trial   = (1:nTrials)';
    Start   = NaN(nTrials, 1);
    Stop    = NaN(nTrials, 1);
    Period  = NaN(nTrials, 1);
    nPulses = zeros(nTrials, 1);
    Source  = repmat({'none'}, nTrials, 1);

    for i = 1:nTrials
        tr = SessionData.RawEvents.Trial{i};
        t0 = SessionData.TrialStartTimestamp(i);
        if ~isfield(tr.Events, startEvent)
            continue;   % camera trigger not started in this trial
        end
        starts = tr.Events.(startEvent);

        % Stop: entry of StopState, else the trial end
        stopRel = SessionData.TrialEndTimestamp(i) - t0;
        if isfield(tr.States, opt.StopState) && ~isnan(tr.States.(opt.StopState)(1))
            stopRel = tr.States.(opt.StopState)(1);
        end

        if numel(starts) > 1
            % timer events were on: every pulse is logged
            onsets = starts(starts < stopRel);
            Source{i} = 'logged';
            if numel(onsets) > 1, Period(i) = median(diff(onsets)); end
        else
            Period(i) = trialPeriod(SessionData, i, opt.Period);
            % 1 ns tolerance: a pulse due exactly at the cancel does not rise
            n = max(0, ceil((stopRel - starts(1)) / Period(i) - 1e-9));
            onsets = starts(1) + (0:n-1)' * Period(i);
            Source{i} = 'rebuilt';
        end

        perTrial{i} = t0 + onsets(:);
        Start(i)   = t0 + starts(1);
        Stop(i)    = t0 + stopRel;
        nPulses(i) = numel(onsets);
    end

    ttl = vertcat(perTrial{:});
    if isempty(ttl), ttl = zeros(0, 1); end
    info = table(Trial, Start, Stop, Period, nPulses, Source);
end

function period = trialPeriod(SessionData, i, fixed)
% Pulse period of trial i: the 'Period' option, else the trial's settings
    if ~isempty(fixed)
        period = fixed;
        return;
    end
    gui = struct();
    if isfield(SessionData, 'TrialSettings') && numel(SessionData.TrialSettings) >= i ...
            && isfield(SessionData.TrialSettings(i), 'GUI')
        gui = SessionData.TrialSettings(i).GUI;
    end
    if ~isfield(gui, 'TTLPeriod')
        error('bpod_camera_ttl:period', ['Trial %d has no TrialSettings.GUI.TTLPeriod. ' ...
            'Pass the pulse period with ''Period''.'], i);
    end
    period = gui.TTLPeriod;
end
