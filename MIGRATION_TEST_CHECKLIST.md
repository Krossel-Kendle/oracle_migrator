# Kapps Schema Migrator - Manual Test Checklist

## 1. Connection and metadata loading
- Start one instance in `Server` mode, one in `Source`, one in `Target`.
- On `Server`, enable `Server active` and set password (if used).
- On `Source` and `Target`, connect to server with matching password.
- Verify on `Server`:
  - `Source State = Connected`
  - `Target State = Connected`
  - schema lists load into both comboboxes
  - after schema selection, tablespace comboboxes are auto-filled
  - target tablespace can be selected from the loaded list

## 2. Migration precheck
- Click `Migrate`.
- Verify log contains remote precheck lines with discovered tool paths:
  - `sqlplus`
  - `expdp`
  - `impdp`
- Verify precheck validates Oracle login (`SYS` + `PDB`) on both agents before export/import.
- Verify migration stops with clear error if any tool is missing.

## 3. End-to-end run
- Ensure schema/password values are filled.
- Run migration and verify stages:
  - `Precheck`
  - `PrepareFolders`
  - `PrepareDirectory`
  - `Export`
  - `Transport`
  - `Clean` (if enabled)
  - `Import`
  - `PostCheck`
- Verify final state `Completed` and progress `100%`.

## 4. File transfer integrity
- During transport, verify progress lines for transferred files.
- Confirm files are present:
  - on target: `<AgentDpumpRoot>\current\*.dmp`
  - on server cache: `<ServerCacheRoot>\<jobId>\*.dmp`
- Confirm import log is fetched to:
  - `<ServerCacheRoot>\<jobId>\target_logs\imp_<schema>.log`

## 5. Artifacts and diagnostics
- Confirm server writes:
  - `<ServerCacheRoot>\<jobId>\server_migration.log`
  - `<ServerCacheRoot>\<jobId>\summary.txt` (includes result + warning/error counters)
- Verify secrets are masked in streamed export/import lines.

## 6. Failure behavior
- Stop Source or Target during migration.
- Verify migration fails quickly with explicit error (no long hang on pending RPC).
- Reconnect agents and rerun migration.
