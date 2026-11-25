import assert from 'node:assert/strict';
import { mkDistractionEvent, mkRecoveryEvent } from '../../browser_extension/src/shared/event-schema.js';
import { syncEventQueue } from '../../browser_extension/src/background/database-sync.js';

const url = new URL(process.argv[2]);
assert.equal(url.hostname, '127.0.0.1');
const started = Date.now() - 20000;
const session = { session_id: crypto.randomUUID(), active: true, started_at: started };
const event = mkDistractionEvent({
  domain: 'instagram.com', category: 'social', escalation_level: 1,
  session_id: crypto.randomUUID(), distraction_count: 1, distraction_started_at: started,
});
const storage = {
  fe_supabase_url: url.origin, fe_backend_url: url.origin, fe_supabase_anon_key: 'fixture',
  fe_user_id: 'fixture-user', fe_auth_token: 'fixture-token', fe_event_queue: [{ event }],
};
globalThis.chrome = { storage: { local: {
  get: async () => ({ ...storage }), set: async values => Object.assign(storage, values),
} } };
// The event belongs to a previous session whose parent is still offline.
assert.deepEqual(await syncEventQueue(session), { synced: 1, remaining: 0 });
storage.fe_event_queue.push({ event: mkRecoveryEvent({
  event_type: 'recovery', domain: event.domain, session_id: event.session_id,
  related_event_id: event.id, from_level: 1, distraction_started_at: started,
  time_on_site_ms: 20000,
}) });
assert.deepEqual(await syncEventQueue(session), { synced: 1, remaining: 0 });
