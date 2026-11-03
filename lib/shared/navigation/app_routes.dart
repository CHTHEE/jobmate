/// Central route paths used by GoRouter and page navigation.
abstract final class AppRoutes {
  static const home = '/';
  static const signUp = '/sign-up';
  static const verifyEmail = '/verify-email';
  static const forgotPassword = '/forgot-password';
  static const verifyPassword = '/verify-password';
  static const changePassword = '/change-password';
  static const terms = '/terms';
  static const privacy = '/privacy';
  static const profile = '/profile';
  static const company = '/company';
  static const jobPostings = '/job-postings';
  static const browseJobs = '/jobs';
  static const applications = '/applications';
  static const applicants = '/applicants';
  static const createJob = '/job-postings/create';
  static const documentSubmission = '/document-submission';
  static const inviteAdmin = '/invite-admin';
  static const adminPermissions = '/admin-permissions';
  static const adminUsers = '/admin-users';
  static const companyReviews = '/admin-company-reviews';
  static const notifications = '/notifications';

  /// Kept in memory so email addresses do not appear in the browser URL.
  static String pendingAuthEmail = '';
  static bool pendingEmailCooldown = true;
}
