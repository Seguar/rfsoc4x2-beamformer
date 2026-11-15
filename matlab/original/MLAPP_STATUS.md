# .mlapp status: binary PENDING, exported AppBase class delivered

Delivered: `app/VSA_rfsoc_refactor_exported.m`, a runnable AppBase class. Its
`createComponents` and `updateAppLayout` are copied verbatim from the original export
(original lines 971–1757). The one changed line is the final `Visible='on'` → `'off'`;
`startupFcn` shows the window only when `cfg.visible=true`. The integrated
export is the source of truth for this refactor; its private initial generator is
not included because replaying it would discard the subsequent review fixes.

**Not delivered: an editable `.mlapp`.** Reasons:

1. The original package is an OPC zip: `matlab/document.xml` (code, embedded class name
   `VSA_rfsoc`), `appdesigner/appModel.mat` (component model), screenshot and metadata.
   The embedded code matches the export (1796 lines each, identical `startupFcn`). The
   export's class name is `VSA_rfsoc_exported`.
2. R2026a has no documented headless API that saves an App Designer app. What exists is
   `appdesigner` (opens the GUI) plus internal, undocumented
   `appdesigner.internal.serialization.MLAPPSerializer` / `PlainTextSerializer`. An
   internal serializer would also have to regenerate `appModel.mat`. Replacing only
   `document.xml` in the zip would leave `appModel.mat` stale, so that was not done.
3. Therefore no `.mlapp` was written and the original `VSA_rfsoc.mlapp` /
   `VSA_rfsoc_exported.m` were not changed. They stay consistent with each other.

Ways to get the editable file (the parent or user decides; it needs the App Designer GUI):

- Open `VSA_rfsoc.mlapp` in App Designer, Save As `VSA_rfsoc_refactor.mlapp` (class
  `VSA_rfsoc_refactor`), paste the code sections from `tools/head.m.part` / `tail.m.part`
  into the editable areas (startup with `varargin`, private methods, callbacks, delete),
  save, export, then diff the export against the delivered `.m`.
- Or, on R2025a+, save the app in App Designer's plain-text `.m` format, which App Designer
  can open as an app. Use the GUI for this, not an internal serializer.
