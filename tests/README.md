# Regression checks

Use MATLAB with Signal Processing Toolbox, with the repository root on the path.

```matlab
addpath(pwd)
results = runtests('tests');
assertSuccess(results)
```

From a shell, change folder inside MATLAB: a `startup.m` that changes the
folder overrides `-sd`, and `runtests('tests')` then finds no tests and still
succeeds.

```
matlab -batch "cd('<repository root>'); addpath(pwd); results = runtests('tests'); assertSuccess(results)"
```

The numerical tests cover event boundaries and masks, independent thresholds,
ETA time origins, duplicates and missing samples, recording boundaries and
random controls and smoothing limits. `test_windows`
covers sub-window placement on multiple monitors, the session reset after the
last module window closes, and the remembered dialog folder. `test_sessions`
writes session files and reads them back (selected modules only, format
marker `fileFormat = 'KineSync session'`, `formatVersion = 5`) and checks that
other files, older and newer formats are rejected. `test_ephys` covers the ephys
data types (Raw, Processed 1..N, renumbering after delete, `has('ephys')` with
processed data only, frame timing from the synchronization without data, the obsolete trigger dropped from older files), the ephys
`.mat` file (selected types, processed-only loading, rejected files),
down sampling onto an exact grid from time 0 and the four filter types, the
TTL channel labels (count, width, rate) and the frame-rate sources (a typed-in
rate replaces the synchronized times; clearing it returns to automatic), and joining
Open Ephys recordings (time from the first sample, gaps kept, TTLs from every
recording; overlaps, changed stream, rate or channels are refused) and
down-sampling leaving timestamp gaps as NaN. `test_files` covers DLC csv frame
numbers (a zoom-window save keeps the original frame numbers; on open a
cropped file is shifted to 1 when the video has the same number of frames,
otherwise padded with NaN) and the behavior `.mat` file (round trip, zoom window
as NaN plus mask, rejected files). `test_video` covers the marker rasterizer
(positions, ring alpha by time, scale, grayscale, missing points) and the
export (padding to even size, frame count and rate, abort and a writer
closed from outside both leave a playable file).

Close KineSync before running the desktop integration test:

```matlab
results = runtests('tests/test_behav_ui.m');
assertSuccess(results)
```

This checks body-part/trace switching, the mask editor without per-body-part `.trace`,
preview versus commit, threshold persistence, all-false masks and invalidation
after a failed calculation, and the menu bar: launcher closing, Window menu
checkmarks and sub-windows, and Exit all resetting the session; and that
restoring a session replaces all module windows and brings back window
positions, widget values, data, frame rate, time and zoom; and that ephys
pre-processing adds Processed types from the selected source (with the
requested rate and `parameters.Source`), the delete button is off while the
pre-process window is open, and deleting every type keeps the synchronization; and that the digital channel
menu draws a channel, Synchronize is enabled only with digital channels and
frames, the Synchronize window's presets, counts, count-mismatch refusal, NaN
dropping and both-edge counts, and that the result sets `ephys.sync`, the pose
times and the frame rate. `test_review_fixes` covers `Shared.convert_time`. The viewers
are closed with `Shared.exit_all(false)`, which skips the close confirmations.
It is skipped without a desktop MATLAB session.

Manual checks of the menu bar and windows:

- The launcher closes when a module opens from a button, the Window menu or
  Load session; running `KineSync` while modules are open raises them instead.
- Window menu: checkmarks follow open modules; open sub-windows are listed,
  indented, under their module and disappear when closed; Bring All to Top
  leaves the invoking window on top.
- Close and the window's X ask before closing a module window; sub-windows
  close without asking; Exit all asks once.
- After Exit all, or after closing the last module window, a new `KineSync`
  has no leftover frame rate, time, zoom or path.
- Sub-windows opened near a screen edge or on a second monitor are fully
  visible, title bar (and the ETA menu bar) included.
- Titles show the opened file, also after Load session; file dialogs start in
  the folder of the last file opened.
- Shortcuts in every window with a menu: Ctrl+O Open, Ctrl+S Save, Ctrl+W
  Close, Ctrl+I/E/P/B open or raise Video/Ephys/Pose/Behavior, Ctrl+A Open All,
  Ctrl+T Bring All to Top.

Manual checks with representative recordings are still required:

- Load single and consecutive RHD/RHS files; verify sample/channel counts and TTL rate.
- Switch to a recording without camera TTL; verify the old synchronization and processed data are gone.
- Load Intan and Open Ephys recordings; check the digital channel menu labels (count,
  width, rate) and that a chosen channel is drawn in yellow on the right axis, event
  markers over the trace and the time line under it.
- Load pose CSV/HDF5/MAT files (DeepLabCut format, also SLEAP's DeepLabCut-format csv export); inspect markers at known frames.
- Use a video whose encoded rate differs from acquisition rate; check first, consecutive,
  jumped-to and last frames, and playback speed.
- Save a session with a rate override, selected body part/trace, thresholds, time and zoom;
  reload over another session and after restarting; check all four viewers.
- Save session lists the open modules, all selected; save only some and check
  that loading reopens just those. With no module open it shows an alert.
- Load session asks once when module windows are open, not from the launcher;
  a non-session or old session file shows an alert and closes nothing.

Manual checks of Ephys:

- Pre-process Raw, then pre-process Processed 1: the preview (yellow)
  overlays the selected source; the dropdown lists Raw, Processed 1, 2.
- The ✕ button asks before deleting the selected type (also Raw); remaining
  processed types are renumbered; with everything deleted the dropdown shows
  "no data", plots disappear, and the video still uses the synchronized timing.
- Save with several types offers a selection; the title switches to the saved
  file. Choosing the `.mat` the ephys data was opened from is refused.
- Ephys Open File with one or several .rhd/.rhs files joins them; Open folder
  still reads Intan and Open Ephys folders; mixing .mat with other files is
  refused.
- Open File with a .mat lists raw/processed with sizes; open only a processed type and
  check plots, channel map/sort, ETA and zoom without raw data.
- Open Ephys folder with several recordings: the list shows
  `experimentN/recordingM (length)` in numeric order, all selected; joined
  recordings keep their gaps (TTL edges line up with the trial boundaries);
  recordings from different experiments show an alert and the previous data
  stays; down-sampled data is empty in the gaps.
- Without open-ephys-matlab-tools on the path, opening an Open Ephys folder
  prints a message, shows a message box with the install link, and stops.

Manual checks of Pose and Behavior files:

- Pose Save, full length and zoom window: the title switches to the saved
  file; choosing the file it was opened from is refused; a fix preview that
  was not committed is not in the file.
- Open the zoom-window csv with the full video open: an info alert says it
  was padded, and markers match the video at known frames. With a video
  cropped to the same frames it is shifted instead.
- Behavior Save, then Open in a new session: body parts, trace, event type, thresholds,
  resolution, min interval, mask and ETA history come back; events match.
  A zoom-window save shows only that part, the rest masked.
- Behavior Open with a different frame rate warns. A behavior file imported from the
  Pose viewer follows pose edits after Open only if the Pose viewer has the
  same file open.

Manual checks of the video export (File > Save in the video window):

- Full length and zoom window; quality prompt defaults to 80. Markers in the
  file match the window: cyan + at the pose point (no fix preview), magenta
  event circles fading with time, same size as on screen.
- During the export Play reads Abort (n%), the slider shows progress, the
  image updates, marker dragging and other controls are off, and other
  windows stay usable. Afterwards the window is back at the current time.
- Abort, closing the video window, and Exit all during the export each leave
  a playable partial file; the source video cannot be chosen as output.
- Preview a pose correction, switch body part/settings and Save As; check source identity.

Validation performed in the editing environment: MISS_HIT parsed all 38 MATLAB
files without parser errors; 23 low-priority pre-existing name/value style notices
remain. `git diff --check` passed. One hundred randomized Python comparisons
validated the ETA normalization formula against direct event-window averaging.
MATLAB/Octave were unavailable: the MATLAB tests have been written but not run.
