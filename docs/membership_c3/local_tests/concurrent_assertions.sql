-- DRAFT / NOT APPROVED FOR DEPLOYMENT. DISPOSABLE LOCAL TEST DATABASE ONLY.
SELECT c3_assert((SELECT status='hired' FROM job_applications WHERE application_id=c3_uid(511)),'concurrent acceptance Hired');
SELECT c3_assert((SELECT count(*)=1 FROM company_memberships WHERE user_id=c3_uid(111) AND company_id=c3_uid(311)),'concurrent acceptance one member');
SELECT c3_assert((SELECT count(*)=1 FROM private.hiring_membership_acceptances WHERE application_id=c3_uid(511)),'concurrent acceptance one receipt');
SELECT c3_assert((SELECT count(*)=1 FROM application_status_history WHERE application_id=c3_uid(511)),'concurrent acceptance one history');
SELECT c3_assert((SELECT count(*)=1 FROM notifications WHERE user_id=c3_uid(211)),'concurrent acceptance one notification');
