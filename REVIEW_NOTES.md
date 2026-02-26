# Review Notes (Current Iteration)

## Fixed in this iteration
- Added remote precheck stage in distributed pipeline.
- Added Oracle tool/path checks + DB login validation on agents before migration.
- Added schema/tablespace existence checks in precheck.
- Added import-log pullback from target to server cache.
- Added server-side job artifacts (`server_migration.log`, `summary.txt`).
- Added transfer retry and disconnect fast-fail for pending RPC.
- Reworked tablespace UI fields to dynamic comboboxes.
- Added connect/disconnect UX for source/target agent buttons.
- Removed thread-unsafe UI access from server worker thread for progress masking.

## Residual risks
- Full compile/run validation requires Delphi IDE/CI (CLI compiler is unavailable in this environment).
- Protocol is still single-RPC at a time (intentional simplification); parallel stage RPC is not implemented.
- Agent DB host/port is fixed to localhost:1521 by design in this build.

## Next potential improvements
- Optional cancellation workflow for running migration.
- Add explicit protocol version field and compatibility checks.
- Add configurable import/export parallelism in settings/UI.
