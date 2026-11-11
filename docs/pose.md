# Pose viewer and correction

The Pose viewer shows body-part trajectories from DeepLabCut or SLEAP and
corrects tracking errors. The Behavior viewer then uses the corrected body parts.

![Pose viewer: x and y traces of a forepaw with event markers and the body-part list](images/pose-viewer.png)

## Supported files

`File > Open` (Ctrl+O):

| Format | Notes |
|---|---|
| DeepLabCut `.csv` | Three header rows (scorer, bodyparts, coords). The frame-index column is kept. Multi-animal files add an `individuals` row; each body part is then listed as `<animal>_<bodypart>`, e.g. `mouse_1_nose` |
| DeepLabCut `.h5` | The `df_with_missing` table written by DeepLabCut |
| `.mat` | A variable `markerpos.<bodypart>.<x, y, likelihood>` |
| SLEAP | Export the predictions from SLEAP in DeepLabCut CSV format and open that file |

Each body part has *x*, *y* (in pixels) and a likelihood.

## Frame alignment

A pose file may cover only part of a video, for example when the video was
cropped in time before tracking. A DeepLabCut CSV records the original frame
numbers in its first column, and KineSync uses them to line the pose frames
up with the video:

- **Frames already 1…N:** used as they are.
- **Same number of frames as the open video:** the frames are shown as
  frames 1…N of that video, and a message explains this.
- **Otherwise:** each row goes to its own frame number, and missing frames
  are left empty (NaN) up to the video length. A message reports what was
  done.

Duplicate frame numbers are an error. Open the video first if you want the
pose file to be checked against its length.

## Controls

| Control | Action |
|---|---|
| Info | Number of frames, duration, and *x*, *y*, likelihood at the current frame |
| X / Y / P | Show the *x* trace, *y* trace and likelihood (right axis, 0–1) |
| Frame rate | The shared frame rate. Type a rate to override it; clear it for automatic (see [Timing](synchronization.md)) |
| Frame | Current frame number |
| Pose Fix | Open the correction window for the selected body part |
| Body-part list | The body part to display, correct and overlay on the video |
| Delete bodypart | Remove the selected body part from the data (asks first; the last one cannot be deleted) |

The vertical axis is in image pixels and runs downwards, as in the image.
Click a trace to move the cursor. Events from the Behavior viewer appear as
magenta circles on the traces.

## Correcting tracking errors

Pose estimators sometimes jump briefly to a wrong location, for example a
paw label landing on the other paw for a few frames. **Pose Fix** finds these
excursions from the trajectory itself and replaces them by interpolation
through the trustworthy parts.

![Pose auto fix window next to the Pose viewer, showing the correction overlay with its legend](images/pose-fix.png)

### Settings

| Setting | Default | Meaning |
|---|---|---|
| Jump thresh (px) | automatic | A frame-to-frame displacement larger than this is a jump |
| Seed width (frames) | automatic | Segments at least this long are trusted as seeds |

Both are estimated when the window opens. Their buttons, **Auto jump thresh**
and **Auto seed width**, re-estimate them. You can also type your own values.

### How it works

1. **Segmentation.** The trajectory is cut at every jump, i.e. every
   displacement larger than the jump threshold, and at every missing frame.
   This gives a series of segments within which the marker moves smoothly.
2. **Automatic jump threshold.** KineSync builds a histogram of
   log₁₀(frame-to-frame displacement). Normal movement and tracking errors
   form two modes. The threshold is the valley between them. If no clear
   valley exists, the threshold is set at median + 4 robust SD of the log
   displacement. At least 50 valid displacements are needed.
3. **Automatic seed width.** Short tracking errors appear as *out-and-back*
   excursions: a jump away, followed within a few jumps by a jump that nearly
   cancels it. The width is 1.5 × the 99th percentile of the lengths of these
   excursions, so a segment at least this long is unlikely to be an error.
4. **Seeds.** Segments at least the seed width long are taken as correct.
5. **Propagation.** Working outwards from the seeds, round by round:
   - an undecided segment next to a good one is first marked bad (the jump
     between them shows that one of the two is wrong);
   - a segment beyond a bad one is compared with a smooth (pchip)
     interpolation through all good frames. If its frames next to the bad
     stretch lie within the jump threshold of the interpolation, it is
     accepted as good. Otherwise it is marked questionable.

   This repeats until no new segment is accepted.
6. **Output.** *x* and *y* are interpolated (pchip) through the good frames.
   Before the first and after the last good frame, the nearest good value is
   held. The input likelihood is not used. A new likelihood records how each
   frame was judged:

   | Frame status | Likelihood |
   |---|---|
   | Confirmed by you | 1 |
   | Seed | 0.95 |
   | Accepted by propagation | 0.9 |
   | Questionable or undetermined | 0.5 |
   | Rejected by propagation | 0.1 |
   | Rejected by you | 0 |

### Reviewing and editing

**Preview** draws the result over the traces:

| Overlay | Meaning |
|---|---|
| Green dotted line | Interpolated trajectory |
| Orange dashed line | Jump |
| Green o / filled green o | Accepted segment / confirmed by you |
| Red x / red * | Rejected segment / rejected by you |
| Grey x, grey o | Questionable / undetermined segment |
| Orange triangles | Places worth checking: two accepted segments next to each other across a jump, a long rejected stretch (≥ ⅓ of the seed width), or a long interpolated stretch (≥ the seed width) |

Two checkboxes below **Preview** and **Save As** declutter the overlay. They
are greyed out until the first preview, and each preview checks both.
**Show segment labels** shows or hides the o / x / * markers, and **Show
attention signs** the triangles. The interpolated line and the jump lines
always show.

The preview is also shown on the video as a green circle next to the raw
cyan marker.

You can correct the result directly on the *x*/*y* traces:

| Action | Effect |
|---|---|
| Ctrl+click | Add a jump here, or remove the nearest one |
| Shift+click | Mark the segment as good (confirmed) or rejected; click again to toggle |
| Drag a marker in the Video viewer | Move the raw or corrected point on the current frame |

After each edit, only the stretch between the surrounding seeds is
recomputed.

Changing the parameters does not update the preview, so your edits are kept
until you click **Preview** again, which asks before discarding them.

### Keeping the result

**Save As** saves the previewed body part (preview first). It adds the corrected trajectory to the data as a new body part. The
default name is `<bodypart>_FixJ<threshold>W<width>`, which records the
settings used, and the original stays unchanged. The new body part can then
be imported in the Behavior viewer. Closing the correction window discards an
unsaved preview.

To write a file, use `File > Save` in the Pose viewer.

## Saving

`File > Save` (Ctrl+S) writes a DeepLabCut-format CSV with all body parts,
including corrected ones. You can save the full length or only the current
zoom window. The first column keeps the original frame numbers, so a file
saved from a zoom window lines up with the video again when reopened. The
default name is `<file>_KineSync.csv`, and the source file cannot be
overwritten. See [Sessions and files](files.md#pose-files).
