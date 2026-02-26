# Спецификация: трёхзвенное приложение миграции схем Oracle (Delphi 12, VCL x32)

**Документ:** Kapps Schema Migrator — Detailed Spec  
**Платформа:** Microsoft Windows Server (на всех трёх звеньях)  
**Технологии:** Delphi 12, VCL, Win32 (x86), Oracle Client tools (`sqlplus`, `expdp`, `impdp`)  
**Дата:** 2026-02-26  
**Авторская подпись в UI:** Made by Krossel Apps, ссылка https://kapps.at

---

## 0. Краткое описание

Разрабатывается **одно** приложение (один `.exe`), которое может быть запущено **в одном режиме одновременно**:

1. **Server** — координация + транспорт (прокси-хаб) между Source и Target, принимает **ровно одного** Source и **ровно одного** Target, инициирует процесс миграции.
2. **Source (Agent)** — агент на сервере-источнике БД: выполняет экспорт схемы в dpump-папку и **передаёт** dump/log файлы на Server.
3. **Target (Agent)** — агент на сервере-приёмнике БД: **получает** dump/log файлы через Server, выполняет import схемы, возвращает лог/результат на Server.

**Ключевой нюанс (обязательный):** приложение **самостоятельно осуществляет транспорт файлов** (экспортные `.dmp` и `.log`) от Source к Target **через Server**. Никакого внешнего копирования руками/SMB/FTP не предполагается.

---

## 1. Цели и границы

### 1.1. Цели
- Миграция **схемы (schema)** Oracle 21c из одной БД в другую на разных серверах Windows.
- Автоматическое определение tablespace(ов) схемы на Source и Target и генерация корректного `REMAP_TABLESPACE`.
- Автоматическая подготовка DP_DIR и папок dpump на обоих агентах.
- Полный вывод действий в лог в реальном времени, сохранение лога в файл.
- Отработка ошибок: сетевые, Oracle-коннект, отсутствие утилит, блокировки файлов, ошибки grants, проблемы expdp/impdp, разрыв соединения агента.

### 1.2. Не делаем (явно)
- Не мигрируем сам Oracle APEX как инфраструктуру (APEX internal schemas, ORDS schemas и т.п.). Мигрируем **пользовательские схемы приложения**.
- Не решаем сетевые/маршрутные проблемы: приложение лишь показывает диагностику и ошибки.
- Не редактируем listener/tnsnames на хостах.

---

## 2. Основные требования

### 2.1. Режимы работы
- Приложение работает **только в одном режиме** (Server/Source/Target) одновременно.
- Выбор режима осуществляется пользователем в UI через табы. После выбора режима (активации таба) переключение запрещено до перезапуска приложения.
  - Допустимо добавить кнопку “Stop mode” (опционально). Но по умолчанию — перезапуск.

### 2.2. Ограничения на соединения
- Server принимает максимум:
  - 1 Source
  - 1 Target
- Любые дополнительные подключения должны быть отклонены с сообщением причины: “Source already connected” / “Target already connected”.

### 2.3. ОС и dpump
- На всех хостах Windows Server.
- DP_DIR в Oracle должен указывать на существующую папку Windows, доступную на запись аккаунту, под которым работает Oracle Database service.
- При нажатии **Migrate** приложение обязано:
  - очистить папки `current` на Source и Target,
  - гарантировать, что в `current` находятся только файлы текущей миграции.

### 2.4. Пароли и спецсимволы
- Пароли могут содержать спецсимволы (`!@#$%^&*()[]{};:'",.<>?/\|` и т.п.).
- Запрещено формировать командную строку через `cmd.exe`/shell с неэкранированными паролями.
- Все вызовы `sqlplus/expdp/impdp` должны выполняться через **parfile** и/или через безопасное подключение без вывода секретов в лог.
- В логах пароли маскируются `********`.

### 2.5. Grants и ошибки грантов
- Требование: “граны и прочее всегда выдаём, даже если с ошибками выдаваться будут”.
- Значит:
  - при `impdp` **не исключать** `OBJECT_GRANT`/`GRANT` по умолчанию,
  - ошибки вида `ORA-01917: user or role ... does not exist` считаются **warning**, не “fatal” (см. классификацию ошибок).

---

## 3. UI: общие требования

### 3.1. Главная форма
- `TMainForm`, VCL.
- `TPageControl` с 3 табами: **Server**, **Source**, **Target**.
- Статусбар снизу (общий): текущая операция и состояние соединений.
- Все длительные операции выполняются в фоновых потоках. UI не блокируется.

### 3.2. Окно Log
- Отдельная **не модальная** форма `TLogForm`.
- Содержит:
  - `TMemo` (read-only) — потоковый лог,
  - `TButton Save output` → `TSaveDialog` → сохраняет текущий лог.
- Лог можно закрывать, открывать через кнопку `Show Log`.
- При старте новой миграции лог очищается и начинает отображать **только текущую** миграцию.

---

## 4. Tab “Server” — UI и логика

### 4.1. Верхний GroupBox Server
**Элементы:**
- `Server active` (checkbox)
- `Server port` (edit numeric)
- `Password (optional)` (password edit)

**Поведение:**
- При включении `Server active`:
  - запускается TCP listener на указанном порту.
  - статус “Listening …”.
- При выключении:
  - listener останавливается,
  - Source/Target отключаются (если были подключены),
  - состояние UI сбрасывается в “Disconnected”.

### 4.2. GroupBox Source
**Элементы:**
- Caption `State`: Connected (зелёный), Disconnected (красный)
- Поля:
  - `PDB` (edit) — по умолчанию `ORCLPDB`
  - `SYS` (edit) — `sys` или `system`
  - `SYS password` (password edit)
  - `Schema` (combo) — заполняется **только после подключения Source**
  - `Tablespace` (edit, Enabled=False) — автоопределение по выбранной схеме
  - `Schema password` (password edit) — пароль схемы на источнике (может отличаться от target)

**Правила:**
- Пока Source не подключён, `Schema` disabled.
- После подключения Source:
  - Server запрашивает у Source список схем и заполняет combo.
- При выборе Schema:
  - Server запрашивает у Source определение tablespace(ов), заполняет `Tablespace` (см. §8.3).

### 4.3. GroupBox Target
**Элементы:** идентичны Source:
- `PDB`, `SYS`, `SYS password`, `Schema` (combo), `Tablespace` (readonly), `Schema password`
- Дополнительно:
  - `Clean before import` (checkbox)

**Поведение:**
- Аналогично Source: список схем только после подключения Target.
- При выборе Schema:
  - автоопределение target tablespace(ов).

### 4.4. GroupBox Actions
**Элементы:**
- Кнопка `Migrate`
- Кнопка `Show Log` (Visible=False изначально)

**Поведение:**
- Нажатие `Migrate`:
  1) мгновенно открывает `TLogForm` (немодально),
  2) `Migrate.Enabled := False`,
  3) `Show Log.Visible := True`.
- По окончании миграции:
  - `Migrate.Enabled := True`,
  - `Show Log` остаётся видимой.
- При повторном нажатии `Migrate`:
  - лог очищается перед стартом новой миграции.

### 4.5. Progress/Status/Footer
- Под Actions:
  - ProgressBar
  - StatusBar: текущая операция (“Preparing folders…”, “Exporting…”, …)
  - Footer: “Made by Krossel Apps” + ссылка `https://kapps.at` (ShellExecute).

---

## 5. Tab “Source” (Agent)

**Элементы:**
- `Server IP`
- `Port`
- `Password`
- `Connect` button
- `Status` caption под кнопкой: Connected/Disconnected/Auth Failed/Connection failed + цвет.

**Логика:**
- Connect:
  - TCP connect к Server,
  - handshake (пароль опционально),
  - регистрация как `AgentType=Source`,
  - далее ожидание команд от Server.

---

## 6. Tab “Target” (Agent)

Полностью аналогичен Source, но регистрируется как `AgentType=Target`.

---

## 7. Протокол и транспорт файлов (ОБЯЗАТЕЛЬНО)

### 7.1. Канал
- TCP соединение с framing (длина + тип сообщения).
- Сообщения:
  - JSON для команд/ответов
  - бинарные chunks для файлов

### 7.2. Требования к транспорту
- Файлы экспорта (`*.dmp`, `exp_*.log`) должны быть доставлены Source → Server → Target **самим приложением**:
  - Source читает файл с диска и отправляет на Server чанками.
  - Server принимает, временно хранит (в server dpump-cache) и пересылает Target.
  - Target сохраняет в свой `current`.

### 7.3. Хранилище на Server
- Server должен иметь локальную папку кеша (конфиг, default):
  - `C:\dpump\kapps_migrator_server\cache\<job_id>\`
- При завершении job:
  - либо удалять кеш (по умолчанию),
  - либо архивировать (опциональный флаг).

### 7.4. Надёжность передачи
- Передача чанками (например 1–4 MB).
- Для каждого файла:
  - метаданные: имя, размер, SHA-256 (или CRC32 для скорости; SHA-256 предпочтительнее)
  - Target после получения сверяет checksum.
- При несовпадении checksum:
  - повторить передачу файла (N раз, default 2),
  - если не удалось — fatal error (job fail).

### 7.5. Лимиты
- Одновременно передаётся один файл (упрощает).
- Поддержка больших файлов (несколько гигабайт) обязательна.
- UI должен показывать прогресс передачи (байты/процент).

---

## 8. Oracle-часть: операции и скрипты

### 8.1. Требования к окружению на агенте
На Source и Target должны быть доступны:
- `sqlplus.exe`
- `expdp.exe`
- `impdp.exe`
в PATH или задана папка Oracle Client в настройках приложения (опционально).

При Precheck агент обязан проверить наличие этих файлов и вернуть Server явную ошибку, если чего-то нет.

### 8.2. Directory и dpump путь (Windows)
**Структура папок на агенте (default):**
- `C:\dpump\kapps_migrator\current\`
- `C:\dpump\kapps_migrator\tmp\`
- (опционально) `archive\`

**Правило:** DP_DIR должен ссылаться на `...\current\`.

### 8.3. Автоопределение tablespace(ов)
После выбора schema агент выполняет запросы (в PDB):

1) Default tablespace:
```sql
SELECT default_tablespace
  FROM dba_users
 WHERE username = :SCHEMA;
```

2) Фактические tablespace сегментов (важно для корректного remap):
```sql
SELECT tablespace_name, COUNT(*) cnt
  FROM dba_segments
 WHERE owner = :SCHEMA
 GROUP BY tablespace_name
 ORDER BY cnt DESC;
```

**Отображение в UI:**
- Если найден один TS → вывести его в `Tablespace`.
- Если TS несколько → вывести:
  - основной (max cnt) в `Tablespace`
  - и логировать предупреждение “Multiple tablespaces detected”.
  - Server обязан применить `REMAP_TABLESPACE` для каждого TS либо потребовать от пользователя mapping (см. §8.4).

### 8.4. Маппинг tablespace (обязательное поведение)
**Минимальная реализация (MVP):**
- Если у схемы на Source обнаружено несколько tablespace:
  - Server автоматически маппит **все** Source TS → Target “главный” TS (тот, что auto определён в target `Tablespace`).
  - В лог добавить: “Auto-mapping all source tablespaces to target tablespace …”.

**Рекомендовано (расширение):**
- Отдельная таблица mapping в UI (не требуется в текущей постановке), но алгоритм выше обязателен как fallback.

### 8.5. Создание/обновление DIRECTORY DP_DIR (скрипт)
На Source и Target агент должен выполнить через `sqlplus`:

```sql
whenever sqlerror exit 1

CREATE OR REPLACE DIRECTORY DP_DIR AS 'C:\dpump\kapps_migrator\current';

GRANT READ, WRITE ON DIRECTORY DP_DIR TO FINDGAMER;

exit
```

Путь должен быть подставлен реальный из настроек агента.

### 8.6. Экспорт (expdp) — строго через PARFILE
Создаётся файл (в `tmp\`) например:
- `exp_<jobid>.par`

Содержимое (пример):
```
userid=FINDGAMER/<SOURCE_SCHEMA_PASSWORD>@//<SRC_IP>:1521/ORCLPDB
schemas=FINDGAMER
directory=DP_DIR
dumpfile=findgamer_%U.dmp
logfile=exp_findgamer.log
parallel=4
compression=all
exclude=statistics
```
> Допустимо выполнять `expdp` под `system`/`sys` (на основе введённых `SYS/SYS password`) — тогда schema password может не понадобиться. Но поля schema password остаются в UI как обязательные для универсальности.

Запуск:
- `expdp parfile="C:\dpump\kapps_migrator\tmp\exp_<jobid>.par"`

### 8.7. Импорт (impdp) — строго через PARFILE
`imp_<jobid>.par`:

```
userid=FINDGAMER/<TARGET_SCHEMA_PASSWORD>@//<TRG_IP>:1521/ORCLPDB
schemas=FINDGAMER
directory=DP_DIR
dumpfile=findgamer_%U.dmp
logfile=imp_findgamer.log
parallel=4
transform=segment_attributes:n
remap_tablespace=<SRC_TS1>:<TRG_TS_MAIN>
remap_tablespace=<SRC_TS2>:<TRG_TS_MAIN>
...
```
- `remap_tablespace` строка повторяется для каждого source TS.
- `transform=segment_attributes:n` обязателен по умолчанию (снижает привязку к storage-атрибутам).

**Grants НЕ исключаем.** Ошибки grants — warning (см. §9).

Запуск:
- `impdp parfile="C:\dpump\kapps_migrator\tmp\imp_<jobid>.par"`

### 8.8. Post-check на Target
После импорта Target выполняет:
1) компиляцию:
```sql
BEGIN
  DBMS_UTILITY.compile_schema(schema => 'FINDGAMER');
END;
/
```
2) отчёт по invalid:
```sql
SELECT object_type, COUNT(*) cnt
  FROM dba_objects
 WHERE owner='FINDGAMER' AND status='INVALID'
 GROUP BY object_type
 ORDER BY cnt DESC;
```

Результат отправляется на Server и отображается в логе.

---

## 9. Clean before import (Target)

### 9.1. Требование
Если `Clean before import` включён, Target должен гарантировать, что старая схема не влияет на результат. Надёжный способ — **пересоздание схемы**.

### 9.2. Алгоритм (пересоздание схемы)
Target выполняет под SYS/SYSTEM:
1) Проверить, что schema существует.
2) `DROP USER <SCHEMA> CASCADE;`
3) `CREATE USER <SCHEMA> IDENTIFIED BY "<TARGET_SCHEMA_PASSWORD>" DEFAULT TABLESPACE <TARGET_TS_MAIN> TEMPORARY TABLESPACE TEMP;`
4) Выдать минимум:
   - `GRANT CREATE SESSION TO <SCHEMA>;`
   - `ALTER USER <SCHEMA> QUOTA UNLIMITED ON <TARGET_TS_MAIN>;`
5) Продолжить `impdp`.

**Важно:** если политика запрещает DROP USER — это должно быть отдельной настройкой (не входит в MVP). Тогда миграция с CleanBeforeImport должна завершиться fatal error с ясным текстом: “DROP USER запрещён политикой, выключите CleanBeforeImport или предоставьте права”.

---

## 10. Оркестрация: последовательность миграции (Server инициатор)

### 10.1. Precheck (Server → Source/Target)
Server запрашивает у агентов:
- ping/health
- наличие `sqlplus/expdp/impdp`
- проверку Oracle connect:
  - подключение к `//<ip>:1521/<pdb>` введёнными SYS данными (или schema данными)
  - запрос `select 'OK' from dual`
- готовность dpump папок (проверка create/write/delete).

**Если любой precheck провален** → миграция не стартует, `Migrate` включается обратно, лог содержит причину.

### 10.2. Prepare folders (Server командует)
- Source:
  - создать/проверить `C:\dpump\kapps_migrator\current`
  - очистить `current`
  - создать `tmp`
- Target:
  - то же самое
- Server:
  - очистить свой cache folder для job

Если очистка не удалась из-за lock — fatal error.

### 10.3. Prepare Oracle DIRECTORY (Server командует)
- Source: создать/обновить DP_DIR → `...\current`
- Target: создать/обновить DP_DIR → `...\current`
- Ошибка создания DIRECTORY/GRANT READ WRITE → fatal.

### 10.4. Export (Source)
- Source запускает expdp, поток stdout/stderr передаётся на Server (и в Log).
- По завершении Source формирует список файлов для передачи:
  - `findgamer_*.dmp` (все части)
  - `exp_findgamer.log`
- Если expdp завершился с ошибкой и dump отсутствует → fatal.

### 10.5. Transport (Source → Server → Target)
- Source отправляет файлы на Server.
- Server сохраняет в cache и пересылает Target.
- Target сохраняет в свой `current`.
- По каждому файлу: checksum validation.

### 10.6. Optional Clean (Target)
- Если включено CleanBeforeImport — выполнить §9.

### 10.7. Import (Target)
- Запустить impdp, поток stdout/stderr направить на Server.
- Ошибки грантов ORA-01917 и подобные — warning.
- Критические ошибки impdp (невозможность открыть dump, повреждённый dump, нет прав) — fatal.

### 10.8. Post-check (Target)
- compile_schema + invalid report.
- Отправить summary на Server.

### 10.9. Завершение
- Server выставляет итог:
  - **Success** — без fatal, warnings допускаются
  - **Success with warnings** — warnings > 0
  - **Failed** — есть fatal
- `Migrate.Enabled := True`

---

## 11. Классификация ошибок (строго)

### 11.1. Fatal (останавливаем job)
- Нет соединения Source или Target.
- Auth failed.
- Нет `sqlplus/expdp/impdp`.
- Не создана dpump папка / нет прав / не очищается.
- Не создан DP_DIR / нет GRANT READ WRITE.
- expdp не создал ни одного dump файла.
- Повреждение dump / checksum mismatch после всех ретраев.
- impdp не может открыть dump / отсутствуют dump файлы.
- Разрыв соединения во время экспорта/транспорта/импорта.
- CleanBeforeImport включён, но DROP USER невозможен.

### 11.2. Warning (job продолжается)
- `ORA-31684: USER already exists`
- `ORA-39083` + `ORA-01917: user or role ... does not exist` (ошибки grants)
- Наличие invalid объектов после компиляции (фиксируется в отчёте)
- Multiple tablespaces detected → auto-mapping применён

### 11.3. Connection failed vs Auth failed (UI)
- Connection failed: TCP connect error/timeout.
- Auth failed: handshake отказ.

---

## 12. Логирование (обязательные требования)

- Каждый этап логируется:
  - `[time] [stage] message`
- Команды выводятся без секретов:
  - parfile путь можно логировать, но содержимое parfile с паролями — нет.
- STDOUT/STDERR expdp/impdp/sqlplus:
  - транслируется в лог с маскированием паролей.
- Кнопка `Save output` сохраняет текущий лог целиком в `.txt`.

---

## 13. Реализация: Delphi 12 (конкретика)

### 13.1. Сокеты
- Разрешается Indy (`TIdTCPServer`, `TIdTCPClient`) или WinSock.
- Требование: поддержка больших файлов, chunked transfer, checksum.

### 13.2. Запуск внешних процессов
- Запрещено: `ShellExecute('cmd.exe', '/c expdp ...')`
- Обязательно: `CreateProcessW` напрямую для `sqlplus.exe`, `expdp.exe`, `impdp.exe` + пайпы stdout/stderr.
- Таймауты:
  - export: по умолчанию 12 часов
  - import: по умолчанию 12 часов
- При таймауте — завершить процесс и job → fatal.

### 13.3. Потоки
- Все операции миграции — в background threads.
- UI обновления через `TThread.Queue`/`Synchronize`.

### 13.4. Конфигурация
- `settings.ini` (минимум):
  - last mode
  - server port
  - dpump root path (agent and server)
  - (опционально) путь к Oracle client bin

Пароли не сохранять.

---

## 14. Тестовые сценарии (покрытие)

1) Source/Target не подключены → Migrate недоступен или выдаёт понятную ошибку.
2) Неверный server password → Auth Failed.
3) Source подключён, Target нет → Migrate запрещён.
4) Oracle connect timeout → fatal на precheck.
5) expdp завершился без dump → fatal.
6) Ошибка grants ORA-01917 → warning, job завершён Success with warnings.
7) CleanBeforeImport включён, нет права DROP USER → fatal.
8) dpump folder locked → fatal.
9) checksum mismatch одного файла → ретраи → если не исправилось → fatal.
10) Мульти-tablespace схема → auto-mapping → import успешен → warning.

---

## 15. Артефакты и результаты

По завершению job должны быть доступны:
- итоговый лог на Server (в UI + сохранить в файл)
- на Target в `current`:
  - `imp_*.log`, `sqlplus` отчёты (если сохраняются)
- (опционально) архив job на Server cache.

---

## 16. Обязательные “details” для разработчика (без двусмысленности)

- Все Oracle команды формируются через `.par` файлы (parfiles), создаваемые на агенте в `tmp`.
- При `Migrate` всегда выполняется очистка папок `current` на Source и Target.
- Передача файлов dump выполняется приложением через Server (Source→Server→Target).
- В `impdp` всегда добавляется `REMAP_TABLESPACE` (как минимум один раз); если source TS несколько — добавляется для каждого.
- Ошибки grants не приводят к остановке job.
- Log window открывается сразу при нажатии `Migrate` и не модальная.
- После старта миграции `Migrate` disabled, `Show Log` visible.
- При старте новой миграции лог очищается.

---

## Приложение A: Минимальный набор сообщений протокола (рекомендовано)

- `Hello` (Agent→Server): type, version, hostname
- `AuthChallenge` (Server→Agent): nonce
- `AuthResponse` (Agent→Server): hash
- `AuthResult` (Server→Agent): ok/fail
- `ListSchemasRequest` / `ListSchemasResponse`
- `GetTablespacesRequest` / `GetTablespacesResponse`
- `PrecheckRequest` / `PrecheckResponse`
- `PrepareFoldersRequest` / `PrepareFoldersResponse`
- `PrepareDirectoryRequest` / `PrepareDirectoryResponse`
- `RunExportRequest` / `RunExportProgress` / `RunExportResult`
- `FileBegin` / `FileChunk` / `FileEnd` / `FileAck`
- `RunCleanRequest` / `RunCleanResult`
- `RunImportRequest` / `RunImportProgress` / `RunImportResult`
- `PostCheckRequest` / `PostCheckResponse`
- `JobSummary`

---

## 17. Product Baseline (фактическая реализация на 2026-02-27)

Ниже фиксируется актуальное состояние продукта в текущей ветке разработки:

- Реализован полный серверный pipeline:
  - `Precheck`
  - `PrepareFolders`
  - `PrepareDirectory`
  - `Export`
  - `Transport`
  - `Clean` (опционально)
  - `Import`
  - `PostCheck`
- Реализован фактический транспорт файлов `Source -> Server -> Target` через приложение.
- Реализована динамическая загрузка metadata:
  - список схем запрашивается у подключенного агента
  - список tablespace запрашивается после выбора схемы
- Реализована проверка целостности файлов:
  - сверка `size` и `SHA-256`
  - повторная перезакачка проблемного файла (до 3 попыток)
- Реализован `Clean before import` через пересоздание target-схемы.
- Реализовано сохранение параметров подключения агентов в `settings.ini`:
  - `source_server_ip`, `source_agent_port`, `source_agent_password`
  - `target_server_ip`, `target_agent_port`, `target_agent_password`
- Реализованы серверные артефакты job:
  - `server_migration.log`
  - `summary.txt`
  - копия target import log в `target_logs`
- В статусбаре во всех режимах отображается подпись:
  - `Made by Krossel Apps | https://kapps.at`

## 18. Подтвержденные ограничения текущей версии

- Одновременно поддерживается не более одного Source и одного Target.
- Одновременно выполняется только один migration job на экземпляр Server.
- Подключение к Oracle на агенте выполняется локально (`127.0.0.1:1521`) с указанным `PDB`.
- Транспорт использует JSON + Base64 (не raw binary stream), что может снижать максимальную пропускную способность на быстрых каналах.
- TLS-шифрование транспортного TCP-канала не реализовано.

## 19. Troubleshooting (RU)

### 19.1. Agent подключается, но на Server нет `Connected`

Проверить:

- одинаковый пароль между Server и Agent
- правильный IP/port
- firewall/ACL по порту сервера
- что экземпляр запущен в правильном режиме (`Source` или `Target`)

### 19.2. Схемы/tablespace не подгружаются на Server

Проверить:

- состояние соответствующего агента = `Connected` на Server
- заполнены ли на Server для этой стороны `PDB`, `SYS`, `SYS password`
- валидность SYS-учетных данных и доступ к указанному PDB

### 19.3. `sqlplus executable not found`, хотя файл есть

Проверить:

- параметр `oracle_client_bin` в `settings.ini`
- права пользователя процесса на каталог Oracle client
- `%ORACLE_HOME%` и наличие `bin\sqlplus.exe`

Допустимые значения `oracle_client_bin`:

- путь к каталогу `...\bin`
- полный путь к `sqlplus.exe`/`expdp.exe`/`impdp.exe`

### 19.4. Ошибки импорта `ORA-01031`, `ORA-31633`, `job does not exist`

Как правило, причина в недостаточных правах target-схемы/квотах.

Проверить:

- grants/roles для схемы назначения
- quota на target tablespace
- корректность clean stage (если включен)

### 19.5. Медленная передача файлов

Факторы:

- overhead JSON/Base64
- CPU-ограничения на Source/Server/Target
- антивирус/EDR, блокировки и инспекция трафика

Что уже реализовано для ускорения:

- увеличенный размер chunk
- переиспользование file stream на read-стороне
- контроль хэшей и перезакачка проблемного файла

### 19.6. `Clean before import` не проходит

Проверить:

- права SYS/SYSTEM на `DROP USER ... CASCADE` и `CREATE USER`
- ограничительные политики безопасности в целевой среде

Если policy запрещает drop user, запускать без clean.

## 20. Рекомендуемые эксплуатационные настройки

- Держать `agent_dpump_root` на локальном SSD.
- Исключить рабочие папки мигратора из realtime AV-сканирования (по политике безопасности организации).
- Контролировать `server_cache_keep_days` для ограничения роста server cache.
- Для воспроизводимых прогонов хранить `server_migration.log` и `summary.txt` как обязательные артефакты релиза.

