-- =============================================================================
-- MISSION CONTROL — clients table (⑦ Client Revenue panel)
-- Paste this whole file into the Supabase SQL Editor and run it.
-- =============================================================================
--
-- Tracks ACTUAL paying clients (not the outreach pipeline) and their monthly
-- revenue. The dashboard sums monthly_fee_zar where payment_status = 'paid'
-- to drive the Revenue Tracker MRR.
--
-- CURRENCY: monthly_fee_zar is South African Rand (ZAR), numeric(12,2).
-- Plans / pricing: website R2,500 · website_plus_reviews R5,000 · full_stack R6,500
-- =============================================================================


-- gen_random_uuid() lives in pgcrypto (enabled by default on Supabase).
create extension if not exists pgcrypto;


-- -----------------------------------------------------------------------------
-- clients
-- -----------------------------------------------------------------------------
create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  company_name text not null,
  niche text check (niche in ('pest control','plumbers','electricians','roofers','gardeners')),
  plan text not null default 'website' check (plan in ('website','website_plus_reviews','full_stack')),
  monthly_fee_zar numeric(12,2) not null default 2500,
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','overdue','cancelled')),
  start_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table  clients                 is 'Actual paying clients. Total MRR = sum(monthly_fee_zar) where payment_status = ''paid''.';
comment on column clients.plan            is 'website (R2,500) | website_plus_reviews (R5,000) | full_stack (R6,500).';
comment on column clients.payment_status  is 'pending | paid | overdue | cancelled.';

create index if not exists idx_clients_status on clients (payment_status);


-- -----------------------------------------------------------------------------
-- Keep updated_at fresh on every UPDATE.
-- (set_updated_at() already exists from the main schema; redefined here so this
--  file is standalone-runnable.)
-- -----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_clients_updated_at on clients;
create trigger trg_clients_updated_at
  before update on clients
  for each row execute function set_updated_at();


-- -----------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- The dashboard runs browser-side with the ANON key, so it needs read + write
-- policies (same public-by-URL tradeoff as revenue_log). The Add Client form
-- inserts; changing a payment status updates.
-- -----------------------------------------------------------------------------
alter table clients enable row level security;

drop policy if exists "anon read clients"   on clients;
drop policy if exists "anon insert clients" on clients;
drop policy if exists "anon update clients" on clients;

create policy "anon read clients"   on clients for select using (true);
create policy "anon insert clients" on clients for insert with check (true);
create policy "anon update clients" on clients for update using (true) with check (true);


-- =============================================================================
-- DONE. Sanity check:
--   select payment_status, count(*), sum(monthly_fee_zar)
--   from clients group by payment_status;
-- =============================================================================
