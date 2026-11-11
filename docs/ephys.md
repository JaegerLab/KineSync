# Ephys viewer

The Ephys viewer reads multichannel recordings and synchronizes the frames of
Video, Pose and Behavior to them. Its preprocessing step prepares the signals for
the event-triggered average.

![Ephys viewer: a processed EMG channel with the cursor line, event markers and the channel list sorted by muscle](images/ephys-viewer.png)

## Opening a recording

- `File > Open File` (Ctrl+O) selects one or more `.rhd`/`.rhs` files, or a
  single `.mat` file written by Save (see [Saving and reopening](#saving-and-reopening)).
- `File > Open folder` asks for a **folder**. KineSync detects the format
  from the folder contents.

### Intan (`.rhd`, `.rhs`)

- The selected files, or every `.rhd`/`.rhs` file in the folder, are read and
  joined in file-name order. Intan's software splits long recordings into consecutive files, and
  they are put back together this way.
- All files must have the same sample rate and channels. A warning appears if
  there is a gap between consecutive files.
- The amplifier channels are the analog channels, named by their custom channel names
  from the Intan software.
- Intan's software notch filter (50/60 Hz) is applied if it was enabled in
  the recording.

### Open Ephys

Select the session folder that contains the `Record Node` folder. Reading
needs [open-ephys-matlab-tools](https://github.com/open-ephys/open-ephys-matlab-tools)
on the path; KineSync shows a message if it is missing.

- If there are several record nodes or streams, you are asked to choose one.
- If there are several recordings, they are listed in folder order with their
  lengths, e.g. `experiment1/recording12 (15.2 s)`, and all are selected.
  Recordings with an empty data file (e.g. a trial stopped as soon as it
  started) are not listed. Only the selected recordings are read.
  Any of them can be selected; they are joined into one in time order. Time 0
  is the start of the first selected recording, gaps between recordings are
  kept as real time, and TTL events from all of them are kept. KineSync
  refuses to join recordings, with a message, if two overlap in time (for
  example recordings from different experiments, whose clock restarts), or if
  the stream, sample rate or channels change.
- Across a gap, Raw data is drawn as a straight line. Filtering and smoothing
  treat the samples on either side of a gap as neighbours, so expect a short
  edge effect there. Down-sampling leaves the gaps empty (NaN), so processed
  data is on one regular grid and can be used for the ETA; the ETA refuses
  Raw data with gaps.
- Channels named `CH…` are the analog channels and are scaled to µV from the per-channel
  bit-volts value. `ADC…` channels are read but not displayed.

### Digital channels

After reading, the digital channel menu lists the digital channels with their
pulse counts, widths and rates, e.g. `DIN-00: 30900 TTL, 10 ms, 100 Hz`.
Choosing one draws it in yellow as a 0/1 trace on a right-hand axis, over the
ephys trace. The first item, `Digital channel:`, hides it and the right axis. The menu
reads `No digital channel` if the recording has none, and `No data` before a
recording is opened. Choosing a channel does not synchronize anything.

### Synchronize

**Synchronize** opens the Synchronize window, which places Video, Pose and
Behavior frames on the ephys clock by pairing digital-channel events with frame
numbers (see [Timing and synchronization](synchronization.md#synchronize)).
It is greyed out until the recording has digital channels and Video, Pose or
Behavior data is open. The info line then shows, for example,
`Rate: 20000 Hz, Length: 600.00 s` and
`Synchronized: TTL-02 rising, 59990 anchors, 100 Hz`; otherwise it says
`Not synchronized.`

## Controls

| Control | Action |
|---|---|
| Info | Sample rate and length of the selected data type, and the synchronization |
| Synchronize | Open the Synchronize window |
| Digital channel menu | The digital channel drawn on the right axis; the first item, `Digital channel:`, hides it |
| time | Cursor time; type a value to jump |
| Pre-Process | Open the preprocessing window |
| Data type | `Raw`, `Processed 1`, `Processed 2`, … |
| ✕ | Delete the selected data type (asks first) |
| Load Channel Map | Label channels from a CSV file |
| Channel list | The channel to display (and to use for the ETA) |
| Sort by | Order the channel list by a column of the channel map |

Click the plot to move the cursor. Raw data is drawn in dark blue, processed data
in green and the preprocessing preview in orange. Events from the Behavior viewer
appear as magenta circles on the ephys trace.

## Channel map

A channel map is a CSV file with one row per channel, in recording order. Any
columns can be used. For example:

```csv
Channel,Muscle,Note
0,Rdelt,
1,Rdelt,
2,Rtri,
```

For differential (bipolar) recordings, the file can have two rows per
channel. The first row of each pair is used. Each channel is then listed as
its name followed by the values in its row, and **Sort by** orders the list by
any column, for example by muscle.

## Preprocessing

**Pre-Process** opens the preprocessing window. It processes the data type
currently selected in the viewer, so events can be chained (for example, a
second down-sampling of *Processed 1*). The window shows the settings of the
selected type: the ones a processed type was made with, or the defaults
below for `Raw`. Selecting another type also discards the preview.

![Ephys Pre-Process window: band-stop filter (< 500 Hz, > 5000 Hz), rectify and down-sample to 200 Hz](images/preprocess.png)

| Setting | Default | Description |
|---|---|---|
| Filter | on, High pass | 4th-order IIR (Butterworth): High pass, Low pass, Band pass or Band stop |
| FiltFilt | off | Filter forwards and backwards (zero phase) instead of a causal filter |
| > *f* Hz | 500 Hz | High-pass half-power frequency; a band edge for Band pass and Band stop |
| < *f* Hz | 5000 Hz | Low-pass half-power frequency; a band edge for Band pass and Band stop |
| Rectify | on | Absolute value |
| Fast smooth | off, 250 samples | Moving average over the given number of samples |
| Down sample | on, 200 Hz | Smooth, then resample at exactly the given sample rate |

Only the settings that apply are enabled: FiltFilt and the filter type need
Filter, High pass uses only the > frequency, Low pass only the < one, and the
band filters both. The signs show which frequencies are kept, so for Band
stop they swap: < the lower edge and > the upper one.

**Fast smooth** smooths without changing the sample rate, for example to get
an envelope at the full rate. When down-sampling, the signal is first
smoothed, which acts as an envelope and anti-aliasing filter: with the Fast
smooth window if it is checked, otherwise with a moving average of
2.5 *fs* / rate samples. It is then linearly interpolated at multiples of 1 / rate from time 0, so
the new rate is exactly the value entered. Samples before
time 0 are removed.

A Fast smooth window shorter than the spacing of the down-sampled points
(*fs* / rate samples, e.g. 100 samples from 20 kHz to 200 Hz) skips samples,
so fast changes alias into the result. Preview and Apply & Close then ask
before going on. **Process anyway** is fine when a low-pass filter has already
removed what lies above half the new rate.

- **Preview** processes the selected channel only and draws it in orange.
- **Apply & Close** processes all channels and adds a new data type
  `Processed N`. Earlier results are kept.
- **Cancel** discards the preview.

The settings and source of each processed type are stored with it (see
[Sessions and files](files.md)). A high-pass frequency above the Nyquist
frequency, or a target rate above the source rate, is rejected.

## Deleting data

**✕** deletes the selected data type. Deleting `Raw` frees memory once
processing is done. Raw data then comes back only by opening the recording
again. The remaining processed types are renumbered. The synchronization and
channel names are kept, so video timing is unaffected. The button is disabled
while the preprocessing window is open.

## Saving and reopening

`File > Save` writes chosen data types to a `.mat` file, for the full length
or the current zoom window. `File > Open File` reads it back. You can leave
out the raw data when opening to save memory. See
[Sessions and files](files.md#ephys-files).
