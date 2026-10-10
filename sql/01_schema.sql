-- Outbound Loop: Supabase / Postgres schema (portfolio project, fictional data)
-- Run the files in /sql in number order.

create extension if not exists vector;

-- Country rules (load first: leads and emails reference it)
create table if not exists country_rules (
  country              text primary key check (country in ('A','B','C','D')),
  pitch_angle          text not null,
  tone                 text,
  main_value_prop      text,
  secondary_value_prop text,
  target_titles        text[] default '{}',
  banned_claims        text[] default '{}',
  required_elements    text[] default '{}',
  cta                  text,
  max_words            int check (max_words > 0)
);

-- Leads (contact already enriched)
create table if not exists leads (
  lead_id                  text primary key,
  country                  text not null references country_rules(country),
  company                  text not null,
  domain                   text,
  industry                 text,
  employees                int,
  city                     text,
  contact_name             text not null,
  contact_title            text,
  email                    text not null unique,
  hr_role_open_days        int default 0,
  headcount_growth_pct_6m  int default 0,
  funding_last_12m         boolean default false,
  retention_post_90d       boolean default false,
  personalization_hook     text,
  status                   text not null default 'ready'
                           check (status in ('ready','in_sequence','replied','snoozed','closed','suppressed')),
  current_touch            int not null default 0 check (current_touch between 0 and 5),
  next_touch_due           timestamptz,
  created_at               timestamptz not null default now()
);
create index if not exists leads_status_due_idx on leads (status, current_touch, next_touch_due);

-- Emails: one row per lead per touch, every draft and every failure
create table if not exists emails (
  id          bigint generated always as identity primary key,
  lead_id     text not null references leads(lead_id) on delete cascade,
  touch       int not null check (touch between 1 and 5),
  country     text references country_rules(country),
  subject     text,
  body        text,
  word_count  int,
  checks      jsonb default '{}'::jsonb,
  status      text not null default 'draft' check (status in ('draft','approved','sent','failed')),
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  unique (lead_id, touch)
);
create index if not exists emails_status_idx on emails (status);
create index if not exists emails_country_idx on emails (country);

-- Knowledge base for the reply agent (1536 = OpenAI text-embedding-3-small)
create table if not exists kb_chunks (
  id          text primary key,
  content     text not null,
  embedding   vector(1536),
  created_at  timestamptz not null default now()
);
create index if not exists kb_chunks_embedding_idx on kb_chunks using hnsw (embedding vector_cosine_ops);

-- Replies: model output stored next to the expected answer, so it can be scored
create table if not exists replies (
  id                 bigint generated always as identity primary key,
  reply_id           text unique,
  lead_id            text not null references leads(lead_id) on delete cascade,
  email_id           bigint references emails(id),
  reply_text         text not null,
  received_at        timestamptz not null default now(),
  model_label        text check (model_label in ('interested','question','not_now','not_interested','unsubscribe','wrong_person','out_of_office')),
  expected_label     text check (expected_label in ('interested','question','not_now','not_interested','unsubscribe','wrong_person','out_of_office')),
  model_action       text,
  expected_action    text,
  expected_kb_topic  text,
  draft_answer       text,
  cited_kb_id        text references kb_chunks(id),
  human_approved     boolean,
  handled            boolean not null default false,
  handled_at         timestamptz
);

-- Run log, including the daily heartbeat
create table if not exists run_log (
  id         bigint generated always as identity primary key,
  run_at     timestamptz not null default now(),
  workflow   text not null,
  level      text not null default 'info' check (level in ('info','warning','error')),
  lead_id    text references leads(lead_id) on delete set null,
  message    text,
  details    jsonb default '{}'::jsonb
);

-- Experiments: hypothesis, volume, window, decision rule
create table if not exists experiments (
  id                   bigint generated always as identity primary key,
  name                 text not null,
  hypothesis           text not null,
  country              text references country_rules(country),
  expected_volume      int,
  expected_conversion  numeric(5,2),
  window_start         date,
  window_end           date,
  decision_rule        text,
  result_volume        int,
  result_conversion    numeric(5,2),
  decision             text,
  created_at           timestamptz not null default now()
);

-- Lock every table from the public API. The n8n service key bypasses RLS.
alter table country_rules enable row level security;
alter table leads         enable row level security;
alter table emails        enable row level security;
alter table kb_chunks     enable row level security;
alter table replies       enable row level security;
alter table run_log       enable row level security;
alter table experiments   enable row level security;
