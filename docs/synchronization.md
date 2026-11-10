# Timing and synchronization

All KineSync windows share one clock, in seconds. When ephys data is loaded, this is
the ephys recording's clock: time 0 is the start of the recording. Video, Pose
and Behavior frames are placed on this clock, all on **one frame timeline**: frame
*k* has the same time in every module. Behavior events and the ETA therefore line
up with the ephys samples recorded at the same moment.

## Digital channels

The recommended setup records the camera's exposure trigger on a digital
input of the ephys system. When the ephys recording is opened, its digital
inputs are listed in the digital channel menu of the Ephys viewer:

- **Intan:** the board digital inputs, e.g. `DIN-00`.
- **Open Ephys:** the TTL event lines of the selected stream, e.g. `TTL-01`.

Each item shows the pulse count, the median pulse width and the rate
(1 / median interval between pulses), for example
`DIN-00: 30900 TTL, 10 ms, 100 Hz` or `DIN-01: 1 TTL, 900 s, - Hz`, so the
camera line is easy to recognise. Choosing a channel only draws it on the
right axis; it does not synchronize.

<!-- SCREENSHOT: docs/images/ttl-menu.png. The digital channel menu showing pulse counts, widths and rates. -->

## Synchronize

**Synchronize** in the Ephys viewer opens the *Synchronize* window,
listed under Ephys in the Window menu. The button is greyed out until the
recording has digital channels and Video, Pose or Behavior data is open.

<!-- SCREENSHOT: docs/images/synchronize.png. The Synchronize window: Ephys events on the left, Video/Pose/Behavior frames on the right. -->

The window pairs ephys **events** (left) with **frame numbers** (right):

| Left: Ephys | |
|---|---|
| Digital channel | Same list as the Ephys viewer |
| Edges | `Rising edge`, `Falling edge`, or `Rising and falling edge` (both, in time order: rise, fall, rise, fall, …) |
| *N* events | Number of events |

| Right: Video/Pose/Behavior | |
|---|---|
| Frames | `All frames` fills in `[1:end]`, `Start and stop` fills in `[1, end]`, `Manual selection` leaves the box empty |
| Frame box | A MATLAB vector with one frame number per event. `end` is the last frame; `NaN` drops an event that has no frame (`NaN(1,5)` drops five). Other functions are not accepted. The brackets are optional. Typing makes it a manual selection. |
| *N* frames | Number of frames in the vector, the dropped events, and the frame count of the timeline (the largest of the open modules; each module's count is shown if they differ) |

Frame numbers must be whole numbers from 1 to the last frame, in increasing
order. Examples:

| Vector | Use |
|---|---|
| `[1:end]` | One camera pulse per frame |
| `[1, end]` | Two events, e.g. the start and stop of the camera pulse train |
| `[2:end-1]` | The first and last frames have no pulse |
| `[NaN 1:end]` | The first pulse has no frame (e.g. recording began before the camera) |
| `[1:2000 NaN(1,5) 2001:end]` | Five pulses without a frame in the middle |
| `[1 1000 NaN 2000 3000]` | Edge-set triggers: frames for some events only |

**Synchronize** first checks that the vector has exactly as many entries as
there are events. If not, it shows both counts and changes nothing: select
other frames, or use `NaN` for events without a frame. Otherwise each frame
with an event is an **anchor**, and every frame gets an ephys time from
`Shared.convert_time`:

- between anchors, times are interpolated linearly, so each anchor frame
  gets exactly its event time;
- before the first and after the last anchor, times follow the slope of the
  straight-line fit through all anchors.

A message reports the number of anchors, the frame rate and how far the
anchors are from a straight line. More than 1 ms is flagged: pulses may be
missing or extra, or the wrong channel was chosen.

The result is stored in `data.ephys.sync`:

| Field | Contents |
|---|---|
| `method` | `'All frames'`, `'Start and stop'` or `'Manual selection'` |
| `frames` | The frame vector as typed |
| `syncVideoTime` | Ephys time (s) of every frame |
| `videoAnchor` | Anchor frame numbers |
| `ephysAnchor` | Anchor ephys times (s); with `All frames` the same as `syncVideoTime` |
| `digitalChannelName` | Name of the digital channel |
| `edge` | `'rising'`, `'falling'` or `'both'` |

The synchronization belongs to the ephys recording. It is kept when ephys
data types are deleted, saved in ephys `.mat` files and sessions, and
removed when another recording is opened. A module with fewer or more frames
than `syncVideoTime` converts its frames with the same anchors. Sessions saved
before synchronization (format 4 and older) cannot be loaded.

## Frame rate

Without a synchronization, frame *k* is placed at *k* / frame rate seconds,
so frame 1 is at 1/frame rate, not 0. The frame rate is taken from the first
available of:

1. a rate typed into the frame rate box of the Video, Pose or Behavior viewer;
2. the synchronization: 1 / median frame interval;
3. the frame rate stored in the video file;
4. 1 Hz. In this case the Pose viewer labels its axis "Frame" rather than
   "Time (s)".

The frame rate box shows `Frame rate: … Hz` in every viewer and updates
whenever a module is opened. An automatic rate (2–4) is shown in italics; the
tooltip says where it comes from. Clear the box or type 0 to return to the
automatic rate.

A typed-in rate also replaces the synchronized times: frames are then placed
at *k* / frame rate. The frame rate is also used for conversions such as
speed (cm/s) and minimum event intervals.

## Converting other times

`Shared.convert_time(source_time, source_anchor, target_anchor)` converts
any times with matched anchors, for example Bpod times to the ephys clock
using camera pulses known on both clocks. `tools/bpod_camera_ttl.m` rebuilds
the camera pulse times from a Bpod session file. Options: `'Method'`
(`'linear'` default, `'pchip'`, `'makima'`, `'spline'`, or `'fit'` for the
straight line everywhere), `'MaxResidual'` and `'Offset'`.

## Moving between time and frames

When the cursor is at time *t*, viewers show the frame whose time is nearest
to *t*. Times before the first frame or after the last frame snap to the first
or last frame. Pose markers are hidden on frames beyond the end of the pose
file.

## Shared cursor and zoom

- Clicking a plot, typing a time, typing a frame number, or moving the video
  slider moves the shared cursor in every window.
- Zooming in or out (or panning with the plot tools) in the Ephys, Pose or Behavior
  viewer changes the shared zoom window, and the other viewers follow.
- When the cursor reaches the edge of the zoom window, the window re-centres
  on the cursor, keeping its width.
- **Zoom window** saves (Ephys, Pose, Behavior and Video `File > Save`) use the
  current zoom window as the time range. See [Sessions and files](files.md).
