export type PaymentStatus =
  | "PENDING"
  | "PROCESSING"
  | "SUCCEEDED"
  | "FAILED"
  | "CANCELLED";
export interface Actor {
  id: string;
  role: string;
  status: string;
}
export interface Assignment {
  assignment_id: string;
  employer_id: string;
  job_seeker_id: string;
  job_title: string;
  company_name: string;
  worker_name: string;
  employment_type: string;
  accepted: boolean;
  completed: boolean;
  work_verified: boolean;
  employer_authorized: boolean;
  payment_blocked: boolean;
  amount_minor: number;
  currency: "MYR";
  terms_version: string;
  payer_name: string;
  payer_email: string;
}
export interface Attempt {
  payment_id: string;
  assignment_id: string;
  employer_id: string;
  job_seeker_id: string;
  agreed_amount_minor: number;
  bonus_minor: number;
  amount_minor: number;
  currency: "MYR";
  status: PaymentStatus;
  provider_payment_id: string | null;
  checkout_url: string | null;
  payment_method: string | null;
  failure_reason: string | null;
  created_at: string;
  confirmed_at: string | null;
  terms_version: string;
}
export interface VerifiedBill {
  id: string;
  reference: string;
  collection: string;
  amount: number;
  paidAmount: number;
  paid: boolean;
  state: "due" | "paid" | "deleted";
  url: string;
  method: string | null;
}
export class PaymentError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}
export const pendingIntegration = () =>
  new PaymentError(
    "PAYMENT_INTEGRATION_PENDING",
    "Assignment, attendance and durable payment storage integration is not configured.",
    501,
  );

export function active(actor: Actor) {
  if (
    !actor.id || actor.status !== "active" ||
    !["employer", "job_seeker", "administrator"].includes(actor.role)
  ) {
    throw new PaymentError("FORBIDDEN", "An active account is required.", 403);
  }
}
export function canRead(actor: Actor, assignment: Assignment) {
  active(actor);
  if (
    actor.role === "administrator" ||
    (actor.role === "employer" && actor.id === assignment.employer_id) ||
    (actor.role === "job_seeker" && actor.id === assignment.job_seeker_id)
  ) return;
  throw new PaymentError(
    "FORBIDDEN",
    "This assignment is not accessible.",
    403,
  );
}
export function amount(value: unknown, allowZero = false): number {
  if (
    !Number.isSafeInteger(value) || (value as number) < (allowZero ? 0 : 1) ||
    (value as number) > 999999999999
  ) {
    throw new PaymentError("INVALID_AMOUNT", "Invalid amount in sen.");
  }
  return value as number;
}
export function eligibility(
  actor: Actor,
  assignment: Assignment,
  attempts: Attempt[],
): string | null {
  canRead(actor, assignment);
  if (actor.role !== "employer" || actor.id !== assignment.employer_id) {
    return "Only the assignment employer can pay.";
  }
  if (assignment.employer_authorized !== true) {
    return "Current Company authorization is required to pay this assignment.";
  }
  if (!["part_time", "temporary"].includes(assignment.employment_type)) {
    return "Payment is available for Part-time and Temporary assignments only.";
  }
  if (!assignment.accepted) return "The assignment has not been accepted.";
  if (!assignment.completed) return "Work is not completed.";
  if (!assignment.work_verified) return "Work verification is required.";
  if (assignment.payment_blocked !== false) {
    return "Resolve the work-completion dispute before paying.";
  }
  if (assignment.currency !== "MYR") {
    return "Only MYR sandbox payments are supported.";
  }
  amount(assignment.amount_minor);
  if (attempts.some((a) => a.status === "SUCCEEDED")) {
    return "Sandbox payment already confirmed.";
  }
  if (attempts.some((a) => ["PENDING", "PROCESSING"].includes(a.status))) {
    return "Awaiting provider confirmation. Resume the existing checkout or check status.";
  }
  return null;
}

/** These are NEW ports, not assumptions about the teammate's table names.
 * Implement only after agreeing the integration contract in docs/payment_handling.md. */
export interface AssignmentSource {
  get(id: string): Promise<Assignment>;
  list(actor: Actor, offset: number, limit: number): Promise<Assignment[]>;
}
export interface PaymentStore {
  attempts(assignmentId: string): Promise<Attempt[]>;
  byId(paymentId: string): Promise<Attempt>;
  /** MUST atomically recheck authoritative eligibility/terms, lock assignment,
   * return the same reservation for duplicate IDs/active attempts, enforce one
   * successful payment and fixed agreed+bonus total. Never just insert a row. */
  reserve(
    actor: Actor,
    assignment: Assignment,
    requestId: string,
    bonus: number,
  ): Promise<{ attempt: Attempt; created: boolean }>;
  /** Atomic bind; must tolerate a verified webhook arriving before create returns. */
  attachCheckout(paymentId: string, bill: VerifiedBill): Promise<Attempt>;
  /** Only for a definite create-request rejection with no provider bill bound. */
  rejectCreation(paymentId: string, reason: string): Promise<void>;
  /** Single DB transaction: validate binding/amount, dedupe event, monotonic
   * transition, audit, and notify both parties once on first SUCCEEDED. */
  applyVerified(
    paymentId: string,
    bill: VerifiedBill,
    eventId: string,
  ): Promise<void>;
}
export interface BillplzGateway {
  create(attempt: Attempt, assignment: Assignment): Promise<VerifiedBill>;
  retrieve(billId: string): Promise<VerifiedBill>;
  verifyCallback(
    request: Request,
  ): Promise<{ billId: string; paymentId: string; eventId: string }>;
}

export function verifyBinding(attempt: Attempt, bill: VerifiedBill) {
  amount(attempt.agreed_amount_minor);
  amount(attempt.bonus_minor, true);
  amount(attempt.amount_minor);
  if (
    attempt.agreed_amount_minor + attempt.bonus_minor !==
      attempt.amount_minor ||
    attempt.currency !== "MYR" || bill.reference !== attempt.payment_id ||
    bill.amount !== attempt.amount_minor ||
    (attempt.provider_payment_id !== null &&
      attempt.provider_payment_id !== bill.id) ||
    (bill.paid &&
      (bill.state !== "paid" || bill.paidAmount !== attempt.amount_minor)) ||
    (!bill.paid && bill.state === "paid")
  ) {
    throw new PaymentError(
      "PROVIDER_MISMATCH",
      "Provider amount or payment reference does not match.",
      409,
    );
  }
}

export function verifiedStatus(bill: VerifiedBill): PaymentStatus {
  // Billplz transaction failure does not necessarily close the payable bill.
  return bill.paid && bill.state === "paid"
    ? "SUCCEEDED"
    : bill.state === "deleted"
    ? "CANCELLED"
    : "PENDING";
}
