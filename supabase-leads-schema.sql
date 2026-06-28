-- =============================================================================
-- MISSION CONTROL — Lead Management writes  (Prompt 8 · Leads CRM page)
-- =============================================================================
-- The Leads view lets you change a company's outreach_status (and edit its
-- details) inline. outreach_companies was previously SELECT-only for the anon
-- key, so this adds the UPDATE policy that lets those edits persist from the
-- browser. activity_feed already has an anon INSERT policy ("dash insert
-- activity"), which the status-change logger reuses — nothing to add there.
--
-- Same public-by-URL tradeoff as the rest of the dashboard
-- (see memory: mission-control-architecture). Idempotent — safe to re-run.
-- =============================================================================

drop policy if exists "dash update outreach" on outreach_companies;

create policy "dash update outreach"
  on outreach_companies for update to anon, authenticated
  using ( true )
  with check ( true );

-- =============================================================================
-- DONE.  Quick check:
--   select policyname, cmd from pg_policies
--   where tablename = 'outreach_companies';   -- expect SELECT + UPDATE
-- =============================================================================
