# Kapps Schema Migrator

Kapps Schema Migrator is a Windows Delphi VCL tool for Oracle schema migration in a three-tier topology:

- `Server` orchestrates the process.
- `Source` agent exports and streams files.
- `Target` agent receives files and imports.

One executable (`Project1.exe`) runs in one mode at a time.

## Features

- End-to-end migration pipeline:
  - Precheck
  - Prepare folders
  - Prepare Oracle directory (`DP_DIR`)
  - Export (`expdp`)
  - Transport (`Source -> Server -> Target`)
  - Optional clean before import
  - Import (`impdp`)
  - Post-check (`compile_schema` + invalid objects report)
- Dynamic metadata loading:
  - schema list is requested from connected Source/Target agents
  - tablespace list is requested after schema selection
- Reliable transfer:
  - chunked file transfer over TCP
  - SHA-256 integrity checks
  - automatic file-level retry when transfer/hash validation fails
- Live logs in UI plus persisted artifacts:
  - `server_migration.log`
  - `summary.txt`
  - copied target import logs
- Persistent agent connection settings (`server IP`, `port`, `password`) in `settings.ini`.
- Status bar footer visible in all modes: `Made by Krossel Apps | https://kapps.at`.

## Architecture

- `Server mode`
  - accepts at most one `Source` and one `Target`
  - coordinates RPC-like requests/responses with request IDs
  - stores job artifacts in server cache
- `Source mode`
  - connects to server
  - executes Oracle operations locally on source host
  - serves exported files for transfer
- `Target mode`
  - connects to server
  - receives files into target `current` folder
  - executes import/clean/post-check locally on target host

## Requirements

- Windows (tool is Win32 VCL).
- Oracle client tools on Source and Target hosts:
  - `sqlplus.exe`
  - `expdp.exe`
  - `impdp.exe`
- Network access from Source/Target agents to Server TCP port.
- Oracle privileges:
  - SYS/SYSTEM credentials used for precheck, directory setup, clean, and metadata queries
  - target schema must be able to run import into target tablespace

## Build

1. Open `Project1.dproj` in RAD Studio 12.
2. Select `Win32` target.
3. Build and run.

Command-line `dcc32` availability depends on installed RAD Studio edition/environment.

## Configuration

Runtime settings are stored in `settings.ini` next to the executable.

Example:

```ini
[general]
last_mode=Server
server_port=20381
source_server_ip=212.12.29.185
source_agent_port=20381
source_agent_password=
target_server_ip=212.12.29.185
target_agent_port=20381
target_agent_password=
agent_dpump_root=C:\dpump\kapps_migrator
server_cache_root=C:\dpump\kapps_migrator_server\cache
server_cache_keep_days=14
oracle_client_bin=C:\app\db_home\bin
```

`oracle_client_bin` accepts:

- Oracle `bin` directory path
- full path to one Oracle executable (the app derives neighboring tools)

Resolution order for `sqlplus/expdp/impdp`:

1. `oracle_client_bin`
2. `%ORACLE_HOME%\\bin`
3. Oracle registry homes
4. `PATH`

## How to use

1. Start one instance in `Server` mode.
2. Enable `Server active`, set server port, optional server password.
3. Start one instance in `Source` mode and connect to server.
4. Start one instance in `Target` mode and connect to server.
5. In `Server` tab:
   - provide Source and Target `PDB`, `SYS`, `SYS password`
   - wait for schema comboboxes to auto-populate
   - select source and target schema
   - wait for tablespace comboboxes to populate
   - set schema passwords
   - optionally enable `Clean before import`
6. Click `Migrate`.
7. Monitor progress/log window and check artifacts in server cache.

## Migration artifacts

Per job folder:

- `<ServerCacheRoot>\\<jobId>\\server_migration.log`
- `<ServerCacheRoot>\\<jobId>\\summary.txt`
- `<ServerCacheRoot>\\<jobId>\\target_logs\\imp_<schema>.log` (if available)
- transferred export files in the job folder

## Troubleshooting

### Agent shows `Disconnected` while server is active

- Verify mode lock: agent instance must run in correct mode (`Source` or `Target`).
- Verify server IP/port.
- Verify agent password equals server password.
- Check firewall on server port.

### Server does not load schema/tablespace lists

- Ensure agent is connected and shown `Connected` on Server tab.
- Fill `PDB`, `SYS`, and `SYS password` on Server tab for that side.
- Ensure Oracle SYS credentials are valid for the specified PDB.

### `sqlplus executable not found` although file exists

- Set `oracle_client_bin` in `settings.ini` to exact Oracle `bin` directory or full executable path.
- Verify service/user account running app has access to that path.
- Verify `%ORACLE_HOME%` is correct if relying on environment.

### Import fails with `ORA-01031` / `ORA-31633`

- Target user privileges are insufficient for import job creation.
- Validate grants/quotas for target schema and target tablespace.
- If required by policy, run clean/setup using privileged SYS account and re-check schema grants.

### `Clean before import` fails

- Clean stage recreates target schema (`DROP USER ... CASCADE` + `CREATE USER ...`).
- Ensure SYS account has required privileges and policy allows dropping the user.
- If not allowed, disable clean and retry.

### Transfer is slower than expected

- Current protocol is JSON + Base64 chunk transport (higher overhead than raw binary streaming).
- Verify CPU load on Source/Server/Target, antivirus scanning, and packet inspection.
- Keep server and agents close in network topology when possible.

### Hash mismatch after transfer

- The app automatically retries file transfer.
- If mismatch persists after retries:
  - check disk health on Source/Target/Server
  - check unstable network middleboxes
  - check endpoint security software that may alter/lock files

## Current limitations

- Single active migration job per server instance.
- One connected Source and one connected Target only.
- DB host and port in migration request are currently local on agent side (`127.0.0.1:1521`).
- Transport channel is not TLS-encrypted.

## Additional docs

- `MIGRATION_TEST_CHECKLIST.md`
- `REVIEW_NOTES.md`
- `Product Specification (RU).md`
