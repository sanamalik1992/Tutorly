-- Run this in your Supabase SQL editor (Dashboard → SQL Editor → New query)

create table if not exists tutorly_users (
  id          text        primary key,          -- Apple Sign In sub
  email       text,
  name        text        not null default 'Student',
  is_pro      boolean     not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists tutorly_sessions (
  id          uuid        primary key default gen_random_uuid(),
  user_id     text        not null references tutorly_users(id) on delete cascade,
  started_at  timestamptz not null default now(),
  ended_at    timestamptz,
  seconds_used integer    not null default 0
);

create index if not exists tutorly_sessions_user_date
  on tutorly_sessions (user_id, started_at desc);

create table if not exists tutorly_iap (
  transaction_id           text        primary key,
  original_transaction_id  text        not null,
  user_id                  text        not null references tutorly_users(id) on delete cascade,
  product_id               text        not null,
  purchase_date            timestamptz not null,
  environment              text        not null default 'Production',
  created_at               timestamptz not null default now()
);

create index if not exists tutorly_iap_user
  on tutorly_iap (user_id, created_at desc);
