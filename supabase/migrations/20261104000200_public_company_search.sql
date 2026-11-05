-- Public-facing company search. Run only after reviewing in the existing project.
-- Returns a narrow projection; it does not open the companies table or storage.
create or replace function public.search_public_companies(
  p_query text,
  p_limit integer default 20
)
returns table (
  company_id uuid,
  company_name text,
  industry text,
  location text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_query text := trim(coalesce(p_query, ''));
begin
  if auth.uid() is null or not exists (
    select 1
    from public.users as u
    where u.user_id = auth.uid()
      and u.status = 'active'::public.account_status
  ) then
    raise exception 'An active account is required.';
  end if;

  if char_length(v_query) < 2 or char_length(v_query) > 100 then
    raise exception 'Search for 2 to 100 characters.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 20 then
    raise exception 'Invalid page size.';
  end if;

  return query
  select
    c.company_id,
    c.company_name::text,
    coalesce(c.industry::text, ''),
    coalesce(c.location::text, '')
  from public.companies as c
  where c.verification_status = 'verified'::public.verification_status
    and position(lower(v_query) in lower(c.company_name)) > 0
  order by lower(c.company_name), c.company_id
  limit p_limit;
end;
$function$;

revoke all on function public.search_public_companies(text, integer)
  from public, anon;
grant execute on function public.search_public_companies(text, integer)
  to authenticated;
