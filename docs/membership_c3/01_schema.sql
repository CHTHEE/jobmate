-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED REVIEW SQL.
-- Source/evidence/remaining release blockers: EVIDENCE_INTEGRATION.md.
-- Not deployable as a partial release. Intentional unconditional execution stop.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
DO $c3_draft_guard$
BEGIN
  RAISE EXCEPTION 'DRAFT / NOT APPROVED FOR DEPLOYMENT: unresolved release gates';
END;
$c3_draft_guard$;
-- PROPOSED mapping of all existing rows to active requires explicit CH/KZ approval.
LOCK TABLE public.company_memberships IN ACCESS EXCLUSIVE MODE;
DO $c3_preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Review requires postgres operator to preserve intended object ownership';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid='public.company_memberships'::regclass
      AND conname='company_memberships_pkey' AND contype='p'
      AND pg_catalog.pg_get_constraintdef(oid)='PRIMARY KEY (user_id)')
  THEN RAISE EXCEPTION 'Membership PK differs from evidence'; END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
    WHERE confrelid='public.company_memberships'::regclass AND contype='f')
  THEN RAISE EXCEPTION 'Unreviewed inbound membership FK'; END IF;
END;
$c3_preflight$;
ALTER TABLE public.company_memberships
  ADD COLUMN membership_status text NOT NULL DEFAULT 'active',
  ADD CONSTRAINT c3_membership_status_check
    CHECK(membership_status IN ('active','inactive','revoked'));
CREATE UNIQUE INDEX c3_one_owned_company_per_user_idx
  ON public.company_memberships(user_id) WHERE member_role='owner';
-- Retain jobmate_one_owner_per_company_idx and existing outbound CASCADE FKs.
ALTER TABLE public.company_memberships
  DROP CONSTRAINT company_memberships_pkey,
  ADD CONSTRAINT company_memberships_pkey PRIMARY KEY(company_id,user_id),
  DROP CONSTRAINT company_memberships_member_role_check,
  ADD CONSTRAINT company_memberships_member_role_check
    CHECK(member_role IN ('owner','employer','member'));
CREATE OR REPLACE FUNCTION private.protect_jobmate_company_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
begin
  if tg_op = 'DELETE' then
    if old.member_role = 'owner' then
      raise exception 'A Company Owner cannot be removed.'
        using errcode = 'P0001';
    end if;

    raise exception 'Retain membership history; use lifecycle instead of deletion.';
  end if;

  if tg_op = 'UPDATE'
     and old.member_role = 'owner'
     and (
       new.member_role is distinct from old.member_role
       or new.company_id is distinct from old.company_id
       or new.user_id is distinct from old.user_id
     ) then
    raise exception 'Company ownership cannot be transferred or changed.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id
       or new.company_id is distinct from old.company_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Membership identity and creation history are immutable.';
    end if;
    if old.member_role <> 'owner' and new.member_role = 'owner' then
      raise exception 'Membership updates cannot create ownership.';
    end if;
    if old.membership_status in ('inactive','revoked')
       and new.membership_status = 'active' then
      raise exception 'Reactivation requires a separately reviewed workflow.';
    end if;
  end if;
  if new.member_role = 'owner' then
    if new.membership_status <> 'active' then
      raise exception 'A Company Owner must remain active.';
    end if;
    select role::text
    into v_role
    from public.users
    where user_id = new.user_id for share;

    if v_role is distinct from 'employer' then
      raise exception 'Only an Employer can become a Company Owner.'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$function$;
-- NEW proposed safeguard: exported users trigger list omits the checked-in
-- jobmate_owner_must_remain_employer trigger. Do not claim it is deployed.
-- KZ review + isolated Owner creation/account-role race tests are release gates.
CREATE FUNCTION private.c3_require_owner_employer_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NEW.role::text IS DISTINCT FROM 'employer' AND EXISTS (
    SELECT 1 FROM public.company_memberships m
    WHERE m.user_id=OLD.user_id AND m.member_role='owner'
  ) THEN RAISE EXCEPTION 'A Company Owner must keep the Employer role.'; END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.c3_require_owner_employer_role()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER c3_owner_must_remain_employer BEFORE UPDATE OF role ON public.users
  FOR EACH ROW EXECUTE FUNCTION private.c3_require_owner_employer_role();

-- NEW server-only receipt; new names are proposals, not deployed definitions.
CREATE TABLE private.hiring_membership_acceptances (
  application_id uuid PRIMARY KEY REFERENCES public.job_applications(application_id),
  company_id uuid NOT NULL,
  user_id uuid NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,user_id)
    REFERENCES public.company_memberships(company_id,user_id)
);
ALTER TABLE private.hiring_membership_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.hiring_membership_acceptances FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.hiring_membership_acceptances
  FROM PUBLIC, anon, authenticated, service_role;
-- Intended reviewed operator/new object owner: postgres, matching original
-- SECURITY DEFINER owners. No ordinary role receives management or receipt access.
-- Receipt FKs do not cascade: retain hiring history; no backfill in this draft.
-- No client lifecycle/reactivation API is exposed. Audit/authorization for future
-- administrative lifecycle operations remains a separate approved contract.
COMMIT;