-- ============================================================
-- 家族共有アプリ（どこだっけメモ / 冷蔵庫つかいきりタイマー / 家族の気分天気）
-- Supabase セットアップ用 SQL
-- 使い方: Supabase ダッシュボード → SQL Editor に貼り付けて Run を1回実行
-- 何度実行しても安全なように作ってあります（idempotent）。
-- テーブルはすべて fam_ 接頭辞。PICKLE HUB のテーブルには触りません。
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 世帯（家族） ----------
create table if not exists public.fam_households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

-- ---------- 家族メンバー（名前 + 4桁PINでログイン） ----------
create table if not exists public.fam_members (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  name         text not null,
  pin          text not null,
  created_at   timestamptz not null default now(),
  unique (household_id, name)
);

-- ---------- どこだっけメモ（物の置き場所） ----------
create table if not exists public.fam_items (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  name         text not null,
  place        text not null default '',
  memo         text not null default '',
  category     text not null default 'その他',
  created_by   text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------- 冷蔵庫つかいきりタイマー（食材） ----------
create table if not exists public.fam_foods (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  name         text not null,
  category     text not null default 'その他',
  bought_on    date,
  expiry_on    date not null,
  status       text not null default 'active',  -- active / used / discarded
  memo         text not null default '',
  created_by   text not null default '',
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);

-- ---------- 家族の気分天気（1人1日1件） ----------
create table if not exists public.fam_moods (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  member_id    uuid not null references public.fam_members(id) on delete cascade,
  mood_date    date not null,
  mood         text not null,  -- great / good / ok / bad / awful
  note         text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (member_id, mood_date)
);

-- ---------- インデックス ----------
create index if not exists idx_fam_members_household on public.fam_members(household_id);
create index if not exists idx_fam_items_household    on public.fam_items(household_id);
create index if not exists idx_fam_foods_household    on public.fam_foods(household_id);
create index if not exists idx_fam_moods_household    on public.fam_moods(household_id, mood_date);

-- ============================================================
-- RLS（Row Level Security）
-- このアプリはログイン認証の代わりに「招待コード + 名前 + PIN」を
-- アプリ側で照合する方式のため、anon キーからの読み書きを全許可します。
-- ※ 低センシティビティな家庭用メモ専用の割り切りです。
--   お金・医療など重要な情報は入れないでください。
-- ============================================================
alter table public.fam_households enable row level security;
alter table public.fam_members    enable row level security;
alter table public.fam_items      enable row level security;
alter table public.fam_foods      enable row level security;
alter table public.fam_moods      enable row level security;

drop policy if exists fam_households_anon_all on public.fam_households;
create policy fam_households_anon_all on public.fam_households
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_members_anon_all on public.fam_members;
create policy fam_members_anon_all on public.fam_members
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_items_anon_all on public.fam_items;
create policy fam_items_anon_all on public.fam_items
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_foods_anon_all on public.fam_foods;
create policy fam_foods_anon_all on public.fam_foods
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_moods_anon_all on public.fam_moods;
create policy fam_moods_anon_all on public.fam_moods
  for all to anon, authenticated using (true) with check (true);

-- ============================================================
-- 追加モジュール（歯磨き / 偏頭痛 / 英語 / 家族スケジュール）
-- ============================================================

-- ---------- 歯磨き記録（子どもごと・朝/夜） ----------
-- カメラガイド付き歯磨きセッション自体は端末のブラウザ内で動き、
-- 映像は保存されません。ここに残るのは「できた」記録だけです。
create table if not exists public.fam_brushing (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  member_id    uuid not null references public.fam_members(id) on delete cascade,
  brush_date   date not null,
  slot         text not null,  -- morning / night
  done         boolean not null default true,
  zones_done   int not null default 0,
  source       text not null default 'manual',  -- session / manual
  created_at   timestamptz not null default now(),
  unique (member_id, brush_date, slot)
);

-- ---------- 偏頭痛チェック（メンバーごと・日次） ----------
create table if not exists public.fam_migraine_logs (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  member_id    uuid not null references public.fam_members(id) on delete cascade,
  log_date     date not null,
  risk_score   int not null default 0,       -- 0-100
  risk_level   text not null default '',     -- 低い/やや低い/ふつう/やや高い/高い
  pressure     numeric,                      -- 現在の気圧 hPa
  drop24       numeric,                      -- 24時間の気圧低下 hPa
  sleep        text not null default '',
  stress       text not null default '',
  stiffness    text not null default '',
  headache     boolean not null default false,  -- 実際に頭痛が起きたか
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (member_id, log_date)
);

-- ---------- 英語学習の進み具合（子どもごと） ----------
create table if not exists public.fam_english_progress (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.fam_households(id) on delete cascade,
  member_id    uuid not null references public.fam_members(id) on delete cascade,
  learned      jsonb not null default '[]'::jsonb,  -- おぼえた単語/フレーズのID配列
  stars        int not null default 0,
  stamps       jsonb not null default '[]'::jsonb,  -- 学習した日付の配列
  updated_at   timestamptz not null default now(),
  unique (member_id)
);

create index if not exists idx_fam_brushing_household on public.fam_brushing(household_id, brush_date);
create index if not exists idx_fam_migraine_household on public.fam_migraine_logs(household_id, log_date);
create index if not exists idx_fam_english_household  on public.fam_english_progress(household_id);

alter table public.fam_brushing        enable row level security;
alter table public.fam_migraine_logs   enable row level security;
alter table public.fam_english_progress enable row level security;

drop policy if exists fam_brushing_anon_all on public.fam_brushing;
create policy fam_brushing_anon_all on public.fam_brushing
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_migraine_anon_all on public.fam_migraine_logs;
create policy fam_migraine_anon_all on public.fam_migraine_logs
  for all to anon, authenticated using (true) with check (true);

drop policy if exists fam_english_anon_all on public.fam_english_progress;
create policy fam_english_anon_all on public.fam_english_progress
  for all to anon, authenticated using (true) with check (true);
