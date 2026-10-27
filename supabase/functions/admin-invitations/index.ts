import { withSupabase } from 'npm:@supabase/server@1';

export default {
  fetch: withSupabase(
    { auth: 'user' },
    async (req, ctx) => {
      const json = (body: unknown, status = 200) =>
        Response.json(body, { status });

      if (req.method !== 'POST') {
        return json(
          { error: 'Method not allowed.' },
          405,
        );
      }

      let body: unknown;

      try {
        body = await req.json();
      } catch {
        return json(
          { error: 'Invalid JSON body.' },
          400,
        );
      }

      if (
        body === null ||
        typeof body !== 'object' ||
        !('action' in body) ||
        body.action !== 'check_access'
      ) {
        return json(
          { error: 'Unsupported action.' },
          400,
        );
      }

      const userId = ctx.userClaims?.id;

      if (!userId) {
        return json(
          { error: 'Please log in first.' },
          401,
        );
      }

      try {
        const {
          data: user,
          error: userError,
        } = await ctx.supabase
          .from('users')
          .select('role, status')
          .eq('user_id', userId)
          .maybeSingle();

        if (userError) {
          throw userError;
        }

        if (
          !user ||
          user.role !== 'administrator' ||
          user.status !== 'active'
        ) {
          return json(
            { error: 'An active administrator account is required.' },
            403,
          );
        }

        const {
          data: permissions,
          error: permissionsError,
        } = await ctx.supabase
          .from('administrator_profiles')
          .select(
            'can_manage_admin_permissions, can_invite_admins',
          )
          .eq('user_id', userId)
          .maybeSingle();

        if (permissionsError) {
          throw permissionsError;
        }

        if (!permissions) {
          return json(
            { error: 'Administrator profile was not found.' },
            403,
          );
        }

        return json({
          isAdmin: true,
          canManageAdminPermissions:
            permissions.can_manage_admin_permissions,
          canInviteAdmins:
            permissions.can_invite_admins,
        });
      } catch (error) {
        console.error('Admin access check failed:', error);

        return json(
          { error: 'Unable to check administrator permissions.' },
          500,
        );
      }
    },
  ),
};