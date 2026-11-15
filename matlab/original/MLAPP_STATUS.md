# Editable App Designer artifact

Delivered together:

- `app/VSA_rfsoc_refactor.mlapp`: original119-component model with the refactored controller callbacks.
- `app/VSA_rfsoc_refactor_exported.m`: matching App Designer-generated export.

Both were saved together using MATLAB R2026a internal serialization APIs. Fresh-process
readback checks every component,65 callback links, stored editable/startup code,
MathWorks parser output, and matching99 methods/212 properties. Closing by either
`delete(app)` or window close cleans up the timer, controller and backend.

App Designer generates `delete(app)`, so cleanup lives in `releaseResources`,
registered as a figure-destruction listener. It also generates `Visible='on'` at the
end of component creation. Startup then applies `cfg.visible`; with false, a brief
window flash is possible. Headless tests use a disposable export copy with exactly
that generated show line changed to off. The shipped app/export stay consistent.

Opening/saving/exporting in the App Designer editor has not been checked. The
artifact passed headless model/code readback and parser checks; this is not an editor
round-trip claim. The original source repository and its app are untouched.

Code-only rebuild tools live in `tools/appdesigner/`. They rely on undocumented
R2026a APIs and may require adaptation for another MATLAB release. Preserve the
component model, callback signatures and generated layout; visual component edits
belong in App Designer. Never replace only the ZIP's `document.xml`.
