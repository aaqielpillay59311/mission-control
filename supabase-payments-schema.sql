-- =============================================================================
-- MISSION CONTROL — payments table (⑦ Client Revenue · Payments section)
-- Paste this whole file into the Supabase SQL Editor and run it.
-- =============================================================================
--
-- One row per invoice / payment against a client. The dashboard sums
-- amount_zar where status = 'received' (this calendar month) for "received this
-- month", and where status = 'pending' for the pending total. Marking a payment
-- 'received' in the dashboard also flips the parent client's payment_status to
-- 'paid' (see clients table).
--
-- CURRENCY: amount_zar is South African Rand (ZAR), numeric(12,2).
-- =============================================================================


-- gen_random_uuid() lives in pgcrypto (enabled by default on Supabase).
create extension if not exists pgcrypto;


-- -----------------------------------------------------------------------------
-- payments
-- -----------------------------------------------------------------------------
create table if not exists payments (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid references clients (id) on delete cascade,
  amount_zar     numeric(12,2) not null default 0 check (amount_zar >= 0),
  payment_date   date,
  payment_method text check (payment_method in ('eft','card','cash','paypal')),
  status         text not null default 'pending'
                   check (status in ('pending','received','failed')),
  invoice_number text,
  created_at     timestamptz not null default now()
);

comment on table  payments                is 'Client payments / invoices. Received this month = sum(amount_zar) where status = ''received'' and payment_date in current month.';
comment on column payments.client_id      is 'FK -> clients.id. Cascade-deletes with the client.';
comment on column payments.payment_method is 'eft | card | cash | paypal.';
comment on column payments.status         is 'pending | received | failed. Marking received flips clients.payment_status to paid.';

create index if not exists idx_payments_client  on payments (client_id);
create index if not exists idx_payments_status  on payments (status);
create index if not exists idx_payments_date     on payments (payment_date);


-- -----------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- The dashboard runs browser-side with the ANON key, so it needs read + write
-- policies (same public-by-URL tradeoff as clients / revenue_log). It reads the
-- list, inserts new invoices, and updates status on "Mark as Paid".
-- -----------------------------------------------------------------------------
alter table payments enable row level security;

drop policy if exists "anon read payments"   on payments;
drop policy if exists "anon insert payments" on payments;
drop policy if exists "anon update payments" on payments;

create policy "anon read payments"   on payments for select using (true);
create policy "anon insert payments" on payments for insert with check (true);
create policy "anon update payments" on payments for update using (true) with check (true);


-- =============================================================================
-- DONE. Sanity check:
--   select status, count(*), sum(amount_zar) from payments group by status;
-- =============================================================================
