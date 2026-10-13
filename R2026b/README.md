# Signal Panner for MATLAB R2026b

This folder contains text versions exported using MATLAB R2026b. The
original `.mlapp` files remain in the parent folder for MATLAB R2026a and
visual component design.

## Setup

Use MATLAB R2026b or newer. Set this folder as MATLAB's Current Folder, then
run:

```matlab
addpath(pwd)
SignalPanner_demo
```

Restart App Designer to refresh its Component Library. **SignalPanner** is
registered under **My Components** by this folder's `resources` metadata.
See the [main README](../README.md) for interactions, examples, and the API.

## Editing and File Layout

- `SignalPanner.m` is a code-only component class. Edit it in the MATLAB
  Editor; use the original `SignalPanner.mlapp` for visual component design.
- Keep `SignalPanner_demo.m` and its companion `.xml` file together; both
  files are needed to run the demo. Open the `.m` file in App Designer to
  edit the demo visually.
- Keep `SignalPannerEventData.m` and `resources/` in this folder with the
  component and demo.

Choose one version per MATLAB session. Restart MATLAB before switching
versions, and avoid `addpath(genpath(...))`. Do not leave the original
repository folder as the Current Folder when using the text versions;
the Current Folder takes precedence over the path.

The exported files and helper are separate copies. Changes here do not
update the originals; refresh the exports and helper when maintaining both
versions.

The repository [license](LICENSE.txt) applies to these copies.
