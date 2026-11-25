begin;
create table if not exists public.study_slots (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (length(trim(subject)) between 1 and 120),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at)
);
create index if not exists study_slots_owner_start on public.study_slots(user_id, starts_at);
alter table public.study_slots enable row level security;
drop policy if exists study_slots_owner on public.study_slots;
create policy study_slots_owner on public.study_slots for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.study_slots to authenticated;
-- Existing study_slots owner policies cover planner details.
alter table public.study_slots
  add column if not exists details jsonb not null default '{}'::jsonb
  check (jsonb_typeof(details) = 'object');

-- One snapshot per session. Existing focus_sessions RLS determines ownership.
alter table public.focus_sessions
  add column if not exists studio_summary jsonb
  check (studio_summary is null or jsonb_typeof(studio_summary) = 'object');
notify pgrst, 'reload schema';
commit;

select table_name, column_name, data_type from information_schema.columns
where table_schema = 'public' and (table_name, column_name) in
  (('study_slots','details'), ('focus_sessions','studio_summary'))
order by table_name;
