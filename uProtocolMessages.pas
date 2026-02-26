unit uProtocolMessages;

interface

const
  MSG_HELLO = 'Hello';
  MSG_AUTH_CHALLENGE = 'AuthChallenge';
  MSG_AUTH_RESPONSE = 'AuthResponse';
  MSG_AUTH_RESULT = 'AuthResult';
  MSG_LIST_SCHEMAS_REQUEST = 'ListSchemasRequest';
  MSG_LIST_SCHEMAS_RESPONSE = 'ListSchemasResponse';
  MSG_GET_TABLESPACES_REQUEST = 'GetTablespacesRequest';
  MSG_GET_TABLESPACES_RESPONSE = 'GetTablespacesResponse';
  MSG_PRECHECK_REQUEST = 'PrecheckRequest';
  MSG_PRECHECK_RESPONSE = 'PrecheckResponse';
  MSG_PREPARE_FOLDERS_REQUEST = 'PrepareFoldersRequest';
  MSG_PREPARE_FOLDERS_RESPONSE = 'PrepareFoldersResponse';
  MSG_PREPARE_DIRECTORY_REQUEST = 'PrepareDirectoryRequest';
  MSG_PREPARE_DIRECTORY_RESPONSE = 'PrepareDirectoryResponse';
  MSG_RUN_EXPORT_REQUEST = 'RunExportRequest';
  MSG_RUN_EXPORT_PROGRESS = 'RunExportProgress';
  MSG_RUN_EXPORT_RESULT = 'RunExportResult';
  MSG_FILE_BEGIN = 'FileBegin';
  MSG_FILE_CHUNK = 'FileChunk';
  MSG_FILE_END = 'FileEnd';
  MSG_FILE_ACK = 'FileAck';
  MSG_RUN_CLEAN_REQUEST = 'RunCleanRequest';
  MSG_RUN_CLEAN_RESULT = 'RunCleanResult';
  MSG_RUN_IMPORT_REQUEST = 'RunImportRequest';
  MSG_RUN_IMPORT_PROGRESS = 'RunImportProgress';
  MSG_RUN_IMPORT_RESULT = 'RunImportResult';
  MSG_POSTCHECK_REQUEST = 'PostCheckRequest';
  MSG_POSTCHECK_RESPONSE = 'PostCheckResponse';
  MSG_JOB_SUMMARY = 'JobSummary';

implementation

end.
