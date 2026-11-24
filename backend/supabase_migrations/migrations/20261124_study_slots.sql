create table if not exists public.study_slots (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (length(trim(subject)) between 1 and 120),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at)
);
create index if not exists study_slots_owner_start on public.study_slots(user_id, starts_at);
alter table public.study_slots enable row level security;
create policy study_slots_owner on public.study_slots for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.study_slots to authenticated;
