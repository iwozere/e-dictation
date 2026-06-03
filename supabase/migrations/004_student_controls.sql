alter table public.dictations
  add column if not exists allow_student_controls boolean not null default true;
