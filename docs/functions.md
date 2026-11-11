# Command-line functions

The viewers are built on a few functions that also work on their own, from the
command line or in your own scripts. They take plain arrays, need no open
window and no session, and return plain MATLAB data.

| Function | Purpose |
|---|---|
| [`Ephys.ephys_prep`](#ephysephys_prep) | Filter, rectify, smooth and down-sample ephys data |
| [`Pose.pose_fix`](#posepose_fix) | Correct jumps (mislabels) in a pose trajectory |
| [`Behav.detect_events`](#behavdetect_events) | Find events in a body-part trace |
| [`Behav.eta`](#behaveta) | Event-triggered average with a chance-level control |
| [`Behav.plot_eta`](#behavplot_eta) | Plot a result of `Behav.eta` |

Add the KineSync folder (the one that contains `KineSync.m`) to the path; the
functions are in the packages `+Ephys`, `+Pose` and `+Behav`, so they are called
with the package prefix. `help Pose.pose_fix` and so on print the full help.

## A complete example

```matlab
addpath('C:\path\to\KineSync')

% Ephys: read an EMG recording, rectify and down-sample channel 3 to 1 kHz
rec = Ephys.ephys_read('D:\data\mouse1\emg');
opt = struct('HighPassFreq', 50, 'Rectify', true, 'DownSampleRate', 1000);
[env, t_emg] = Ephys.ephys_prep(rec.analogData(:,3), rec.t, opt, rec.sampleRate);

% Pose: read DeepLabCut output and fix the right hind paw
T = Pose.read_pose('D:\data\mouse1\video1DLC.csv');
[x, y] = Pose.pose_fix(T.RH_x, T.RH_y);

% Behavior: speed in cm/s, then movement onsets
fps = 200; px_per_cm = 20;                       % your camera
speed = Behav.smooth_speed(x, y, 3) * fps / px_per_cm;
t_video = (0:numel(speed)-1)' / fps;             % or frame times from the TTL
events = Behav.detect_events(speed, true(size(speed)), 10, round(0.1*fps), 2);

% ETA of the EMG envelope around the onsets
result = Behav.eta(env, t_emg, t_video(events.onset), 'maxLag', 0.3);
Behav.plot_eta(result);
```

The times passed to `Behav.eta` must be on the ephys clock. In the GUI, video
frames are placed on that clock from the camera TTL pulses (see
[Timing and synchronization](synchronization.md)); in a script you supply the
frame times yourself.

## Ephys.ephys_prep

```matlab
[newData, newT] = Ephys.ephys_prep(data, t, options)
[newData, newT] = Ephys.ephys_prep(data, t, options, fs)
```

Preprocesses ephys data in a fixed order: filter, rectify, smooth and
down-sample. Every step is optional and is switched on by a field of `options`.
This is what **Pre-Process** in the [Ephys viewer](ephys.md) runs.

| Input | Description |
|---|---|
| `data` | Samples × channels. Each column is processed independently |
| `t` | Time of each sample (s), a vector with one value per row of `data` |
| `options` | Struct; leave a field out to skip that step (see below) |
| `fs` | Sample rate (Hz). Default: `1/mean(diff(t))` |

| `options` field | Effect |
|---|---|
| `FilterType` | `'highpass'`, `'lowpass'`, `'bandpass'` or `'bandstop'`: 4th-order IIR (Butterworth). Default: `'highpass'` or `'lowpass'` when only that frequency is given, `'bandpass'` when both are |
| `HighPassFreq` | High-pass cutoff (Hz); a band edge for band filters |
| `LowPassFreq` | Low-pass cutoff (Hz); a band edge for band filters. A band filter passes or stops the band between the two frequencies |
| `FiltFilt` | `true`: zero-phase filtering with `filtfilt`. `false` (default): causal `filter` |
| `Rectify` | `true`: absolute value. Default `false` |
| `SmoothWindow` | Moving-average window in samples (a positive integer), applied after rectifying |
| `DownSampleRate` | New sample rate (Hz). The data are smoothed with a moving window of `SmoothWindow` samples, or 2.5 × `fs/DownSampleRate` without it, then linearly interpolated at `k/DownSampleRate` (*k* = 0, 1, 2, …), so the rate is exact |

| Output | Description |
|---|---|
| `newData` | Processed data |
| `newT` | Time of each output sample |

Samples at negative time (before the recording started) are dropped. A progress
bar is shown while the function runs.

```matlab
% envelope at ~500 Hz, zero-phase filter
opt = struct('HighPassFreq', 30, 'FiltFilt', true, 'Rectify', true, 'DownSampleRate', 500);
[env, t2] = Ephys.ephys_prep(raw, t, opt, 30000);

% band pass 20-450 Hz, no envelope
opt = struct('FilterType', 'bandpass', 'HighPassFreq', 20, 'LowPassFreq', 450);
bp = Ephys.ephys_prep(raw, t, opt, 30000);
```

## Pose.pose_fix

```matlab
[xFix, yFix, mask, seg] = Pose.pose_fix(x, y)
[xFix, yFix, mask, seg] = Pose.pose_fix(x, y, jumpThresh, seedWidth)
[xFix, yFix, mask, seg] = Pose.pose_fix(x, y, jumpThresh, seedWidth, maskOrSeg)
[...] = Pose.pose_fix(..., visualize)
```

Corrects short tracking errors in one body part's trajectory. The trace is cut
into segments at jumps larger than `jumpThresh`. Segments at least
`seedWidth` frames long are trusted seeds, and the remaining segments are
accepted or rejected by comparing them with an interpolation through the
trusted frames. The rejected frames are then replaced by that interpolation.
The algorithm is described in [Pose viewer and correction](pose.md). This is
what **Pose Fix** runs.

| Input | Description |
|---|---|
| `x`, `y` | Coordinates of one body part, in pixels (vectors of equal length) |
| `jumpThresh` | Jump threshold (pixels). `[]` or omitted: estimated by `Pose.auto_jump_threshold` |
| `seedWidth` | Seed width (frames). `[]` or omitted: estimated by `Pose.auto_window_width` |
| `maskOrSeg` | Optional. A logical vector (one value per frame) marks frames you already know to be good (`true`) or bad (`false`): good runs become seeds, bad runs are rejected, and nothing is propagated. A segment structure (`seg` from an earlier call, possibly edited) re-runs the algorithm only around the edited segments |
| `visualize` | `true` to plot the result, with the same layers and styles as the correction overlay in the Pose viewer (`Shared.styles`), plus the suggested fix at each conflict. Default `false` |

| Output | Description |
|---|---|
| `xFix`, `yFix` | Corrected trajectory: a pchip interpolation through the good frames. Before the first and after the last good frame the nearest good value is held |
| `mask` | Logical, `true` for frames in good segments |
| `seg` | Segment structure: start, stop, length and flag of each segment, the jumps, and conflicts with suggested fixes. See `help Pose.pose_seg_build` |

Segment flags in `seg.flag`: 2 seed, 1 good, 0 undetermined, −1 bad,
−2 questionable, −3 rejected. `Pose.seg_likelihood(seg)` turns them into a
per-frame likelihood, as used when the GUI saves a fixed body part.

```matlab
T = Pose.read_pose('video1DLC.csv');            % columns <bodypart>_x/_y/_likelihood
[xf, yf, good, seg] = Pose.pose_fix(T.nose_x, T.nose_y, 20, 60, [], true);

% use likelihood as prior knowledge instead of propagation
[xf, yf] = Pose.pose_fix(T.nose_x, T.nose_y, 20, [], T.nose_likelihood > 0.9);

% mark segment 12 as good by hand, then update only around it
seg.flag(12) = 2; seg.isNew(12) = true;
[xf, yf, good, seg] = Pose.pose_fix(T.nose_x, T.nose_y, [], [], seg);
```

When a segment structure is passed, `jumpThresh` and `seedWidth` default to
the values stored in it. To add or remove a jump in `seg`, use
`Pose.pose_seg_toggle_jump`.

## Behav.detect_events

```matlab
events = Behav.detect_events(trace, mask, threshold, minInterval)
events = Behav.detect_events(trace, mask, threshold, minInterval, nearZero)
```

Finds events in one body-part trace (x, y or speed). The event definitions are
those of the [Behavior viewer](behavior.md#events).

| Input | Description |
|---|---|
| `trace` | Body-part trace, one value per frame |
| `mask` | Logical, `false` for frames to exclude. Use `true(size(trace))` for no mask |
| `threshold` | Threshold in the units of `trace` |
| `minInterval` | Minimum distance between peaks and valleys, in **frames** (a positive integer) |
| `nearZero` | Speed treated as rest, for onset and offset. Default `NaN` (no onsets or offsets). `Behav.auto_rest_threshold(speed, fps)` estimates it as the Behavior viewer does |

`events` is a struct of frame indices (column vectors) into `trace`:

| Field | Event |
|---|---|
| `rising` | Last frame at or below `threshold` before the trace rises above it |
| `falling` | First frame at or below `threshold` after the trace was above it |
| `onset` | Last frame at or below `nearZero` before a rising crossing, back to the previous falling crossing |
| `offset` | First frame at or below `nearZero` after a falling crossing, up to the next rising crossing |
| `peak` | Local maxima at or above `threshold`, with a prominence of at least one SD of the trace |
| `valley` | Local minima at or below `threshold`, same prominence |
| `masked` | First frame of each masked period |

Masked frames are excluded: no event lies in them, and no search crosses them.
Convert indices to times with your frame times, e.g. `t_video(events.peak)`.

## Behav.eta

```matlab
result = Behav.eta(signal, signalT, eventTime)
result = Behav.eta(signal, signalT, eventTime, Name, Value, ...)
```

Averages one ephys channel around a set of event times and estimates the average
expected by chance. See [Event-triggered average](eta.md) for the controls and
how to read the result.

| Input | Description |
|---|---|
| `signal` | One ephys channel (vector). `NaN` samples are left out of the average |
| `signalT` | Time of each sample (s). Must be regularly sampled, without gaps |
| `eventTime` | Event times (s), on the same clock as `signalT`. Events outside the recording are dropped with a warning |

| Name | Default | Description |
|---|---|---|
| `'maxLag'` | 0.5 | The average covers −maxLag to +maxLag seconds |
| `'method'` | `'dither'` | Control: `'dither'`, `'random_time'`, `'isi_shuffle'`, `'global'` or `'none'` |
| `'nRep'` | 100 | Number of surrogate event sets (`dither`, `random_time`, `isi_shuffle`) |
| `'offset'` | 1 | `dither` shifts each event by a random amount in [−offset, offset) s |
| `'zscore'` | `false` | Stored in the result; `Behav.plot_eta` then plots in control SD units |
| `'nStd'` | 3 | Width of the control band in SD |
| `'plot'` | `false` | `true` plots in a new figure; an axes or figure handle plots there |

The controls:

| Method | Surrogate events |
|---|---|
| `dither` | Each real event shifted at random by up to ±`offset` |
| `random_time` | The same number of events at uniformly random times |
| `isi_shuffle` | The real inter-event intervals in random order |
| `global` | No surrogates: mean of the whole trace, SD = trace SD / √(events) |
| `none` | No control |

If a repeated control is estimated to take longer than 5 s, a dialog offers to
continue, switch to `global`, or skip the control.

`result` fields:

| Field | Description |
|---|---|
| `t` | Lag of each sample (s), from −maxLag to maxLag |
| `y` | The ETA |
| `randomMean`, `randomStd` | Mean and SD of the control at each lag |
| `method` | The control actually computed (it may differ after the dialog) |
| `eventNum` | Number of events used |
| `sampleCount` | Number of samples averaged at each lag |
| `sampleRate`, `maxLag`, `nRep`, `offset`, `zscore`, `nStd`, `randomT` | Settings used |

```matlab
r = Behav.eta(env, t_emg, event_times, 'maxLag', 0.3, 'method', 'isi_shuffle', 'nRep', 500);
above = r.y > r.randomMean + r.nStd * r.randomStd;   % lags above the band
```

## Behav.plot_eta

```matlab
ax = Behav.plot_eta(result)
ax = Behav.plot_eta(result, target)
```

Plots a result of `Behav.eta`: the ETA (black line), the control mean (dashed)
with a band of ±`nStd` SD (shaded), a dotted line at lag 0, and the times of
the largest positive and negative deviations from the control mean. `target`
is an axes or figure handle; without it a new figure is opened. The axes are
cleared first. Returns the axes.

With `result.zscore` set (and a control), the plot is in control SD units:
(ETA − control mean) / control SD, so the control mean is 0 and the band is
±`nStd`.

```matlab
figure; tiledlayout(1, 2);
Behav.plot_eta(rTA, nexttile); title('TA');
rGS.zscore = true;
Behav.plot_eta(rGS, nexttile); title('GS (z-score)');
```
