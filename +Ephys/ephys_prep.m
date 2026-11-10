function [newData, newT] = ephys_prep(data, t, options, fs)
% pre-process ephys data, filter, rectify, smooth then downsample
% Syntax
%  [newData, newT] = Ephys.ephys_prep(data, t, options, fs)
%
% Parameters:
%  data: 2-D array, each channel is vertical vector
%  t: 1-D array, time axis.
%  options: a structure with the following optional field
%       FilterType: 'highpass', 'lowpass', 'bandpass' or 'bandstop'.
%           Default: from the frequencies given (both: 'bandpass')
%       HighPassFreq: a number. high pass cutoff (highpass, band edge)
%       LowPassFreq: a number. low pass cutoff (lowpass, band edge)
%           bandpass/bandstop use the band between the two frequencies
%       FiltFilt: boolean. true uses filtfilt, false (default) uses filter
%       Rectify: boolean. true or false(default)
%       SmoothWindow: a number. moving average window in samples
%       DownSampleRate: a number. frequency to down sample to: smooth, then
%           interpolate at multiples of 1/DownSampleRate from time 0.
%           Without SmoothWindow, the window is 2.5*fs/DownSampleRate.
%           Grid points inside timestamp gaps are NaN.
%  fs: sample rate of data (default: from t)
% Outputs:
%  newData: processed data. data at negative time are truncated.
%  newT: down sampled t. negative time are truncated.
%
% Li Su. 2/27/2026

%%
if nargin < 4 || isempty(fs), fs = 1/mean(diff(t)); end
newData = data;

hd = waitbar(0,'Processing ...', 'Name', 'Processing');
closeBar = onCleanup(@()delete(hd));   % also on errors
drawnow

f = makeFilter(options, fs);
if ~isempty(f)
    waitbar(1/6, hd, 'Filtering ...')
    if isfield(options, 'FiltFilt') && options.FiltFilt
        newData = filtfilt(f, newData);
    else
        newData = filter(f, newData);
    end
end

if isfield(options, 'Rectify') && options.Rectify
    newData = abs(newData);
end

% smooth: the given window, or one that suits the down sample rate
smoothWidth = [];
if isfield(options, 'SmoothWindow')
    validateattributes(options.SmoothWindow, {'numeric'}, {'scalar','integer','positive'});
    smoothWidth = options.SmoothWindow;
elseif isfield(options, 'DownSampleRate')
    validateattributes(options.DownSampleRate, {'numeric'}, {'scalar','real','finite','positive','<=',fs});
    smoothWidth = max(1, round(2.5 * fs / options.DownSampleRate));
end
if ~isempty(smoothWidth) && smoothWidth > 1
    waitbar(1/3, hd, 'Smoothing')
    newData = Shared.fastsmooth(newData, smoothWidth,1,1);
end

if isfield(options, 'DownSampleRate')
    validateattributes(options.DownSampleRate, {'numeric'}, {'scalar','real','finite','positive','<=',fs});

    % interpolate on an exact grid k/DownSampleRate, from time 0
    waitbar(2/3, hd, 'Downsampling')
    k = max(0, ceil(t(1) * options.DownSampleRate - 1e-9)) : ...
        floor(t(end) * options.DownSampleRate + 1e-9);
    newT = k(:) / options.DownSampleRate;
    newData = interp1(t, newData, newT, 'linear');
    % no data inside timestamp gaps (e.g. between joined recordings)
    gap = find(diff(t) > 1.5/fs);
    for g = gap(:)'
        newData(newT > t(g) & newT < t(g+1), :) = NaN;
    end
else
    % truncate (discard negative time)
    newData = newData(t>=0,:);
    newT = t(t>=0);
end

clear closeBar

end

function f = makeFilter(options, fs)
% 4th-order IIR (Butterworth) filter described by options, [] for none
f = [];
hasHigh = isfield(options, 'HighPassFreq');
hasLow = isfield(options, 'LowPassFreq');
if isfield(options, 'FilterType')
    type = lower(options.FilterType);
elseif hasHigh && hasLow
    type = 'bandpass';
elseif hasHigh
    type = 'highpass';
elseif hasLow
    type = 'lowpass';
else
    return
end

switch type
    case 'highpass'
        f = designfilt('highpassiir', 'FilterOrder', 4, ...
            'HalfPowerFrequency', options.HighPassFreq, 'SampleRate', fs);
    case 'lowpass'
        f = designfilt('lowpassiir', 'FilterOrder', 4, ...
            'HalfPowerFrequency', options.LowPassFreq, 'SampleRate', fs);
    case {'bandpass', 'bandstop'}
        band = sort([options.HighPassFreq options.LowPassFreq]);
        if band(1) == band(2)
            error('ephys:prep:band', 'The two band frequencies must differ.');
        end
        f = designfilt([type 'iir'], 'FilterOrder', 4, ...
            'HalfPowerFrequency1', band(1), 'HalfPowerFrequency2', band(2), ...
            'SampleRate', fs);
    otherwise
        error('ephys:prep:filterType', 'Unknown FilterType ''%s''.', options.FilterType);
end
end
