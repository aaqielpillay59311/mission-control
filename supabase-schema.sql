-- =============================================================================
-- MISSION CONTROL — Supabase / PostgreSQL schema
-- AI Automation Agency dashboard (single source of truth)
-- =============================================================================
--
-- This script is idempotent-friendly: run the OPTIONAL drop block below first
-- if you need a clean rebuild, then run the whole file in the Supabase SQL Editor.
--
-- It powers three decisions:
--   1. Debt freedom  -> debt_accounts  (avalanche payoff: highest APR first)
--   2. Pipeline health -> outreach_companies
--   3. Revenue to freedom -> revenue_log + financial_snapshot
--   + activity_feed for a live "what just happened" log
--
-- CURRENCY: all money columns are South African Rand (ZAR), numeric(12,2).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- OPTIONAL: clean rebuild. Uncomment these 6 lines to wipe and recreate.
-- WARNING: this DELETES all data in these tables. Leave commented for first run.
-- -----------------------------------------------------------------------------
-- drop table if exists activity_feed     cascade;
-- drop table if exists revenue_log        cascade;
-- drop table if exists outreach_companies cascade;
-- drop table if exists debt_accounts      cascade;
-- drop table if exists financial_snapshot cascade;


-- gen_random_uuid() lives in pgcrypto; it is enabled by default on Supabase,
-- but this makes the script portable to a fresh Postgres too.
create extension if not exists pgcrypto;


-- -----------------------------------------------------------------------------
-- Shared trigger: keep updated_at fresh on every UPDATE.
-- -----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;


-- =============================================================================
-- 1) debt_accounts
-- One row per liability. Drives the avalanche payoff plan (highest APR first).
-- =============================================================================
create table debt_accounts (
  id          uuid primary key default gen_random_uuid(),
  name        text          not null,                 -- e.g. 'Absa Car Loan'
  balance     numeric(12,2) not null check (balance >= 0),  -- outstanding ZAR
  apr         numeric(6,3)  not null check (apr >= 0),       -- interest rate %
  min_pay     numeric(12,2) not null default 0 check (min_pay >= 0), -- min monthly payment ZAR
  target_flag boolean       not null default false,   -- TRUE = the account you're attacking now
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now()
);

comment on table  debt_accounts             is 'Liabilities. Avalanche = pay highest APR first; target_flag marks the current focus account.';
comment on column debt_accounts.apr         is 'Interest rate as PROVIDED (percent). NOTE: these look like MONTHLY rates (1.75 = 1.75%/month ~ 21% p.a.). Keep units consistent in your payoff math.';
comment on column debt_accounts.min_pay     is 'Minimum monthly payment in ZAR. Seeded values are ESTIMATES (~3% of balance / typical installment) — replace with the real figure from each statement.';
comment on column debt_accounts.target_flag is 'TRUE for the single account currently being attacked under the avalanche method.';

create index idx_debt_avalanche on debt_accounts (apr desc, balance asc);

create trigger trg_debt_accounts_updated_at
  before update on debt_accounts
  for each row execute function set_updated_at();


-- =============================================================================
-- 2) outreach_companies
-- Your prospecting CRM: 100 companies across 5 niches.
-- =============================================================================
create table outreach_companies (
  id               uuid primary key default gen_random_uuid(),
  company_name     text not null,
  niche            text not null
                     check (niche in ('pest control','plumbers','electricians','roofers','gardeners')),
  suburb           text,
  email            text,
  website          text,
  demo_site_url    text,                              -- the demo you built for them
  protocol_name    text,                              -- which build/automation protocol you used
  outreach_status  text not null default 'not_started'
                     check (outreach_status in (
                       'not_started','researching','demo_built','contacted',
                       'followed_up','replied','call_booked','proposal_sent','won','lost')),
  deal_value_zar   numeric(12,2) check (deal_value_zar >= 0),  -- expected monthly/contract value
  next_action_date date,                             -- when to touch this lead next
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table  outreach_companies                 is 'Outreach CRM. Pipeline health = volume + movement across outreach_status by niche.';
comment on column outreach_companies.niche           is 'One of: pest control, plumbers, electricians, roofers, gardeners.';
comment on column outreach_companies.outreach_status is 'Funnel stage: not_started -> researching -> demo_built -> contacted -> followed_up -> replied -> call_booked -> proposal_sent -> won/lost.';
comment on column outreach_companies.deal_value_zar  is 'Expected deal value in ZAR (use your monthly retainer figure to map straight onto MRR targets).';
comment on column outreach_companies.next_action_date is 'Next follow-up date — power your daily task list off this.';

create index idx_outreach_status      on outreach_companies (outreach_status);
create index idx_outreach_niche       on outreach_companies (niche);
create index idx_outreach_next_action on outreach_companies (next_action_date);

create trigger trg_outreach_companies_updated_at
  before update on outreach_companies
  for each row execute function set_updated_at();


-- =============================================================================
-- 3) revenue_log
-- Monthly MRR by source. One row per (month, source).
-- =============================================================================
create table revenue_log (
  id          uuid primary key default gen_random_uuid(),
  month       date          not null,                 -- store the 1st of the month, e.g. 2026-06-01
  mrr_amount  numeric(12,2) not null default 0 check (mrr_amount >= 0),
  source      text          not null default 'agency',-- 'agency', 'retainer:AcmePest', 'one-off', etc.
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now(),
  unique (month, source)
);

comment on table  revenue_log            is 'Monthly recurring revenue log. Sum by month to track MRR vs break-even (R10,596) and freedom (R74,000).';
comment on column revenue_log.month      is 'Normalize to the first day of the month (YYYY-MM-01) so months group cleanly.';
comment on column revenue_log.source     is 'Where the revenue came from — keeps room for multiple streams per month.';

create index idx_revenue_month on revenue_log (month desc);

create trigger trg_revenue_log_updated_at
  before update on revenue_log
  for each row execute function set_updated_at();


-- =============================================================================
-- 4) activity_feed
-- Append-only event stream for the live "what just happened" panel.
-- NOTE: requested column "timestamp" is a Postgres reserved type keyword, so it
--       is named event_time here (timestamptz). Query it as event_time.
-- =============================================================================
create table activity_feed (
  id          uuid primary key default gen_random_uuid(),
  event_time  timestamptz not null default now(),     -- your "timestamp" field
  action      text not null,                          -- e.g. 'demo_built', 'email_sent', 'reply_received'
  company     text,                                   -- free-text company name (decoupled from CRM)
  details     text                                    -- human-readable note / JSON-ish blob
);

comment on table  activity_feed            is 'Append-only activity log for the live feed. Newest first via event_time.';
comment on column activity_feed.event_time is 'When it happened (your "timestamp"). Renamed to avoid the reserved word TIMESTAMP.';
comment on column activity_feed.action     is 'Short machine-friendly verb: email_sent, demo_built, reply_received, call_booked, deal_won, payment_received...';

create index idx_activity_time on activity_feed (event_time desc);


-- =============================================================================
-- 5) financial_snapshot  (bonus — needed for decision #3 + runway)
-- Holds the headline numbers that don't belong to any single account.
-- runway_months is COMPUTED, so it can never drift from cash / burn.
-- =============================================================================
create table financial_snapshot (
  id                 uuid primary key default gen_random_uuid(),
  snapshot_date      date          not null default current_date,
  monthly_income_zar numeric(12,2) not null,          -- total monthly income in
  monthly_burn_zar   numeric(12,2) not null check (monthly_burn_zar > 0), -- monthly burn / break-even
  cash_zar           numeric(12,2) not null,          -- cash on hand
  break_even_zar     numeric(12,2) not null,          -- MRR needed to cover burn
  freedom_mrr_zar    numeric(12,2) not null,          -- MRR target = "freedom"
  runway_months      numeric(8,2)
                       generated always as (round(cash_zar / nullif(monthly_burn_zar, 0), 2)) stored,
  created_at         timestamptz   not null default now(),
  unique (snapshot_date)
);

comment on table  financial_snapshot               is 'Headline finances + targets. Take a new row whenever cash/burn/income change to see the trend.';
comment on column financial_snapshot.runway_months is 'AUTO-COMPUTED = cash_zar / monthly_burn_zar. Do not write to it.';


-- =============================================================================
-- HELPER VIEWS — make the dashboard queries one-liners.
-- =============================================================================

-- Decision #1: full avalanche payoff order (highest APR first, smaller balance breaks ties).
create or replace view v_avalanche_plan as
select
  row_number() over (order by apr desc, balance asc) as payoff_order,
  name, balance, apr, min_pay, target_flag
from debt_accounts;

-- Decision #1: one-glance debt totals.
create or replace view v_debt_overview as
select
  count(*)                                                       as account_count,
  sum(balance)                                                  as total_balance_zar,
  sum(min_pay)                                                  as total_min_pay_zar,
  round(sum(balance * apr) / nullif(sum(balance), 0), 3)        as weighted_avg_apr,
  (select name from debt_accounts order by apr desc, balance asc limit 1) as current_target
from debt_accounts;

-- Decision #2: pipeline counts + value, broken down by niche and stage.
create or replace view v_pipeline_by_stage as
select
  niche,
  outreach_status,
  count(*)                              as companies,
  coalesce(sum(deal_value_zar), 0)      as pipeline_value_zar
from outreach_companies
group by niche, outreach_status
order by niche, outreach_status;

-- Decision #2: top-line pipeline health.
create or replace view v_pipeline_totals as
select
  count(*)                                                                                 as total_companies,
  count(*) filter (where outreach_status in
        ('contacted','followed_up','replied','call_booked','proposal_sent'))               as active_conversations,
  count(*) filter (where outreach_status = 'won')                                          as won,
  count(*) filter (where outreach_status = 'lost')                                         as lost,
  coalesce(sum(deal_value_zar) filter (where outreach_status not in ('lost')), 0)          as open_pipeline_zar
from outreach_companies;

-- Decision #3: latest MRR vs break-even and freedom targets.
create or replace view v_revenue_vs_targets as
with latest_month as (
  select month, sum(mrr_amount) as mrr from revenue_log
  group by month order by month desc limit 1
), snap as (
  select break_even_zar, freedom_mrr_zar from financial_snapshot
  order by snapshot_date desc limit 1
)
select
  coalesce((select mrr from latest_month), 0)                                  as current_mrr_zar,
  s.break_even_zar,
  s.freedom_mrr_zar,
  s.break_even_zar  - coalesce((select mrr from latest_month), 0)              as gap_to_break_even_zar,
  s.freedom_mrr_zar - coalesce((select mrr from latest_month), 0)              as gap_to_freedom_zar,
  round(100.0 * coalesce((select mrr from latest_month), 0)
        / nullif(s.freedom_mrr_zar, 0), 1)                                     as pct_to_freedom
from snap s;


-- =============================================================================
-- ROW LEVEL SECURITY
-- The SECRET (service_role) key bypasses RLS — use it server-side for your
-- dashboard backend. The ANON key obeys RLS, so by default it sees nothing
-- until you add a policy. Enable RLS now; uncomment a read policy if you query
-- directly from the browser with the anon key.
-- =============================================================================
alter table debt_accounts      enable row level security;
alter table outreach_companies enable row level security;
alter table revenue_log        enable row level security;
alter table activity_feed      enable row level security;
alter table financial_snapshot enable row level security;

-- Example: allow read-only access to anonymous clients (uncomment to use).
-- create policy "anon read debt"     on debt_accounts      for select using (true);
-- create policy "anon read outreach" on outreach_companies for select using (true);
-- create policy "anon read revenue"  on revenue_log        for select using (true);
-- create policy "anon read activity" on activity_feed      for select using (true);
-- create policy "anon read finance"  on financial_snapshot for select using (true);


-- =============================================================================
-- DATA INSERTS
-- =============================================================================

-- ---- Debt: your 7 real accounts (total R524,043) -----------------------------
-- Ordered as the avalanche attacks them (APR desc, then smallest balance first).
-- target_flag = TRUE on Nedbank: it's tied for the top APR (1.75%) and is the
-- smallest balance, so it gets knocked out first — fastest momentum.
-- min_pay values are ESTIMATES (replace with real statement minimums).
insert into debt_accounts (name, balance, apr, min_pay, target_flag) values
  ('Nedbank',              7975.00,   1.750,  250.00,  true),   -- attack first
  ('Absa CC2',            66877.00,   1.750, 2010.00,  false),
  ('Absa CC1',           110004.00,   1.750, 3300.00,  false),
  ('Capitec Access',     113743.00,   1.750, 3415.00,  false),
  ('Capitec Credit',      50611.00,   1.670, 1520.00,  false),
  ('Absa Personal Loan', 129008.00,   1.440, 3800.00,  false),
  ('Absa Car Loan',       45825.00,   1.020, 1250.00,  false);

-- ---- Financial snapshot: today's headline numbers ----------------------------
-- runway_months auto-computes to 140000 / 10596 = 13.21 (matches your 13.2).
insert into financial_snapshot
  (snapshot_date, monthly_income_zar, monthly_burn_zar, cash_zar, break_even_zar, freedom_mrr_zar)
values
  ('2026-06-28', 35000.00, 10596.00, 140000.00, 10596.00, 74000.00);

-- ---- Revenue baseline: seed the current month at R0 --------------------------
-- (You're pre-revenue / in outreach. Update this and add new rows as MRR lands.)
insert into revenue_log (month, mrr_amount, source) values
  ('2026-06-01', 0.00, 'agency');

-- ---- Outreach: SAMPLE rows only (1 per niche) --------------------------------
-- These are ILLUSTRATIVE so the views/dashboard render. DELETE them and import
-- your real 100 companies:
--     delete from outreach_companies where protocol_name = 'SAMPLE';
insert into outreach_companies
  (company_name, niche, suburb, email, website, demo_site_url, protocol_name, outreach_status, deal_value_zar, next_action_date)
values
  ('Sample Pest Co',     'pest control', 'Sandton',      'hello@example.co.za', null, null, 'SAMPLE', 'demo_built',     4500.00, '2026-07-01'),
  ('Sample Plumbing',    'plumbers',     'Randburg',     'hello@example.co.za', null, null, 'SAMPLE', 'contacted',      3500.00, '2026-07-02'),
  ('Sample Electrical',  'electricians', 'Midrand',      'hello@example.co.za', null, null, 'SAMPLE', 'not_started',    4000.00, '2026-07-03'),
  ('Sample Roofing',     'roofers',      'Centurion',    'hello@example.co.za', null, null, 'SAMPLE', 'replied',        5000.00, '2026-07-04'),
  ('Sample Gardens',     'gardeners',    'Fourways',     'hello@example.co.za', null, null, 'SAMPLE', 'researching',    3000.00, '2026-07-05');

-- ---- Activity feed: one seed event -------------------------------------------
insert into activity_feed (action, company, details) values
  ('schema_initialized', null, 'Mission Control database created and seeded.');

-- =============================================================================
-- DONE. Quick sanity checks:
--   select * from v_debt_overview;          -- total_balance_zar should be 524043.00
--   select * from v_avalanche_plan;         -- Nedbank = payoff_order 1
--   select * from v_revenue_vs_targets;     -- gap_to_freedom_zar = 74000.00
--   select runway_months from financial_snapshot; -- 13.21
-- =============================================================================
