/// Base host for the ChatGPT Android endpoint.
const String kBaseUrl = 'https://android.chat.openai.com';

/// Path prefix used by anonymous (no account) traffic.
const String kAnonPrefix = '/backend-anon';

/// App version reported in the User-Agent. Must match the sentinel payload era.
const String kAppVersion = '1.2026.223';

/// Static Play Integrity failure blob the Android client sends on every turn.
/// Ported verbatim from chatgpt_client.py:119-128 — the backend accepts it as-is.
const String kSentinelPayload =
    '{"bot_token":{"failure_reason":"-9: Standard Integrity API error (-9): '
    'Binding to the service in the Play Store has failed. This can be due to '
    'having an old Play Store version installed on the device.",'
    '"failure_detail":"[aft.y(SourceFile:9), wfo.a(SourceFile:85), '
    'vfo.invokeSuspend(SourceFile:14)]"}}';

/// The only values the backend accepts for `thinking_effort`.
const Set<String> kThinkingEfforts = {'standard', 'extended', 'max'};

/// The only values the backend accepts for `service_tier`.
const Set<String> kServiceTiers = {'standard', 'priority'};
