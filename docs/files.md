# Sessions and files

KineSync saves two kinds of files:

- **Session files** hold everything needed to resume work.
- **Module files** hold one module's data, for sharing or for later analysis
  outside KineSync.

All `.mat` files are written in MATLAB v7.3 format and carry a `fileFormat`
and a `formatVersion` variable, so KineSync can recognise them. Files saved
before the program was renamed from StepSync (`fileFormat` starting with
`'StepSync'`) are not read.

## Sessions

`File > Save session` asks which open modules to include and writes one
`.mat` file. It stores:

- the frame rate, cursor time and zoom window;
- each module's window position, control settings and data.

`File > Load session` closes all module windows (after asking), then reopens
the saved modules exactly as they were.

| Variable | Contents |
|---|---|
| `fileFormat` | `'KineSync session'` |
| `formatVersion` | `5` (older sessions are refused) |
| `frameRate`, `currentTime`, `currentZoom` | Shared timing state |
| `figures` | Window position of each saved module |
| `video`, `ephys`, `pose`, `behav` | Module data, with control settings in `.parameters` |

## Module files

Each module's `File > Save` asks whether to save the **full length** or only
the current **zoom window**. The default file name ends in `_KineSync` (or
`_behav`), and the file a module was opened from is never overwritten.

### Ephys files

`File > Save` in the Ephys viewer asks which data types to save, then writes:

| Variable | Contents |
|---|---|
| `fileFormat`, `formatVersion` | `'KineSync Ephys'`, `1` |
| `ephys` | Channel names and units, synchronization (`sync`), channel map, source, `timeRange` (empty for full length) |
| `raw` | `data` (samples × channels), `t` (s), `sampleRate` (Hz) |
| `processed1`, `processed2`, … | As `raw`, plus `parameters`: `FilterType`, `HighPassFreq`, `LowPassFreq`, `FiltFilt`, `Rectify`, `SmoothWindow`, `DownSampleRate`, `Source` |

Times are on the original recording clock, also in a zoom-window save.
Ephys `File > Open File` with a `.mat` file lists the stored types with their sizes, so you can load
only what you need.

### Pose files

`File > Save` in the Pose viewer writes a DeepLabCut-format CSV:

- three header rows: `scorer`, `bodyparts`, `coords` (`x`, `y`,
  `likelihood`);
- a first column with the zero-based frame number in the original video;
- all body parts, including corrected ones.

Missing values are written as `NaN`. Corrected body parts carry the
likelihood codes described in [Pose viewer and correction](pose.md#how-it-works).

### Behavior files

`File > Save` in the Behavior viewer writes:

| Variable | Contents |
|---|---|
| `fileFormat`, `formatVersion` | `'KineSync behav'`, `2` |
| `behav.paw` | `name`, `rawX`, `rawY` (pixels) and thresholds of each paw |
| `behav.mask`, `behav.maskParam` | The mask and the mask editor's settings |
| `behav.selection` | Selected paw, trace and event type |
| `behav.resolution`, `behav.minInterval`, `behav.frameRate` | Settings |
| `Behav.eta` | ETA history |
| `behav.filename`, `behav.source` | The pose file the paws came from |
| `behav.timeRange` | Empty for full length |

Events, speeds and centimetre traces are not stored. They are
recalculated when the file is opened. In a zoom-window save, frames outside
the window are set to `NaN` and masked, and the frame count is unchanged.

### Videos

`File > Save` in the Video viewer exports an MPEG-4 video with markers drawn
in. See [Video viewer](video.md#exporting-a-marked-video).

## Export to Workspace

`File > Export to Workspace` assigns the session object to a variable in the
MATLAB base workspace (default name `data`; existing variables are not
overwritten). It is the live object, so it reflects later changes in
KineSync. Main fields:

| Field | Contents |
|---|---|
| `data.frameRate`, `data.currentTime`, `data.currentZoom` | Shared state |
| `data.getFrameTimes(n)` | Times (s) of frames 1…n |
| `data.ephys.raw`, `data.ephys.processed(k)` | `data`, `t`, `sampleRate` (and `parameters`) |
| `data.ephys.digital` | Digital channels: `name`, `rise`, `fall` edge times |
| `data.ephys.sync` | Synchronization: `method`, `frames`, `syncVideoTime`, `videoAnchor`, `ephysAnchor`, `digitalChannelName`, `edge` (see [Timing](synchronization.md#synchronize)) |
| `data.pose.table` | Pose table: `<part>_x`, `<part>_y`, `<part>_likelihood` |
| `data.pose.t` | Time of each pose frame |
| `data.behav.t` | Time of each behavior frame |
| `data.behav.mask` | Logical mask (true = analysed) |
| `data.behav.paw(i)` | `name`, `x`, `y` (cm), `speed` (cm/s), and events `rising`, `falling`, `onset`, `offset`, `peak`, `valley`, `masked` (frame indices) |
| `data.behav.eta(j)` | ETA runs: `t`, `y`, `randomMean`, `randomStd`, `sampleCount`, parameters and selections |

Events are only up to date for the paw and trace selected in the Behavior viewer.
