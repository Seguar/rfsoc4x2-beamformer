# Editable App Designer artifact

Delivered together:

- `app/VSA_rfsoc_refactor.mlapp`: the original 119-component model plus 32
  components of one appended tab, **New** (VSA_rfsoc_new port), with the
  refactored controller callbacks.
- `app/VSA_rfsoc_refactor_exported.m`: matching App Designer-generated export.

Both were saved together with MATLAB R2026a internal serialization APIs by
`tools/appdesigner/build_mlapp_ext.m`, from an explicit component spec
(`uiExtensionSpec.m`). Component code comes from App Designer's
ComponentCodeGenerator; the component-declaration and createComponents blocks
are regenerated from the model by `adComponentCode.m`, which first reproduces
the shipped 119-component export byte-exactly. Fresh-process readback
(`verify_mlapp_ext.m`) checks: 151 components, the 119 original components'
property fingerprints unchanged, every spec row (parent, properties, callback
binding), export blocks equal to the reloaded model, 83 callback links, stored
editable/startup code, MathWorks parser output, MLAPPExporter output and equal
class metadata of .mlapp and export.

App Designer generates `delete(app)`, so cleanup lives in `releaseResources`,
registered as a figure-destruction listener. It also generates `Visible='on'` at the
end of component creation. Startup then applies `cfg.visible`; with false, a brief
window flash is possible. Headless tests use a disposable export copy with exactly
that generated show line changed to off. The shipped app/export stay consistent.

Opening/saving/exporting in the App Designer editor has not been checked. The
artifact passed headless model/code readback and parser checks; this is not an editor
round-trip claim. The original source repository and its app are untouched.
