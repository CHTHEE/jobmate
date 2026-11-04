import {
  active,
  amount,
  canRead,
  eligibility,
  PaymentError,
  verifyBinding,
} from "./domain.ts";
import type {
  Actor,
  Assignment,
  AssignmentSource,
  Attempt,
  BillplzGateway,
  PaymentStore,
} from "./domain.ts";

export class PaymentService {
  constructor(
    private source: AssignmentSource,
    private store: PaymentStore,
    private gateway: BillplzGateway,
  ) {}
  private async view(actor: Actor, assignment: Assignment) {
    canRead(actor, assignment);
    const attempts = await this.store.attempts(assignment.assignment_id);
    const reason = eligibility(actor, assignment, attempts);
    // Never send payer email, credentials or internal provider payloads to UI.
    return {
      assignment_id: assignment.assignment_id,
      job_title: assignment.job_title,
      company_name: assignment.company_name,
      worker_name: assignment.worker_name,
      employment_type: assignment.employment_type,
      amount_minor: assignment.amount_minor,
      currency: assignment.currency,
      completed: assignment.completed,
      work_verified: assignment.work_verified,
      payment_blocked: assignment.payment_blocked,
      can_pay: reason === null,
      can_resume_checkout: eligibility(actor, assignment, []) === null &&
        attempts.some((a) => ["PENDING", "PROCESSING"].includes(a.status)),
      blocking_reason: reason,
      attempts: attempts.map((
        { employer_id: _e, job_seeker_id: _j, ...attempt },
      ) => ({
        ...attempt,
        checkout_url:
          actor.role === "employer" && actor.id === assignment.employer_id
            ? attempt.checkout_url
            : null,
      })),
    };
  }
  async list(actor: Actor, offset: number, limit: number) {
    active(actor);
    const assignments = await this.source.list(actor, offset, limit);
    return Promise.all(
      assignments.map((assignment) => this.view(actor, assignment)),
    );
  }
  async get(actor: Actor, assignmentId: string) {
    return this.view(actor, await this.source.get(assignmentId));
  }
  async forPayment(actor: Actor, paymentId: string) {
    active(actor);
    const attempt = await this.store.byId(paymentId);
    return this.get(actor, attempt.assignment_id);
  }
  async create(
    actor: Actor,
    assignmentId: string,
    requestId: string,
    bonus: number,
  ) {
    active(actor);
    amount(bonus, true);
    const assignment = await this.source.get(assignmentId);
    // Validate immutable source rules before accessing the durable reservation.
    const reason = eligibility(actor, assignment, []);
    if (reason) throw new PaymentError("NOT_ELIGIBLE", reason, 403);
    amount(assignment.amount_minor + bonus);
    const reservation = await this.store.reserve(
      actor,
      assignment,
      requestId,
      bonus,
    );
    let attempt = reservation.attempt;
    if (attempt.bonus_minor !== bonus) {
      throw new PaymentError(
        "ACTIVE_AMOUNT_LOCKED",
        "An existing checkout has a different locked Bonus. Refresh payment details before continuing.",
        409,
      );
    }
    if (
      attempt.assignment_id !== assignmentId ||
      attempt.employer_id !== actor.id ||
      attempt.job_seeker_id !== assignment.job_seeker_id ||
      attempt.agreed_amount_minor !== assignment.amount_minor ||
      attempt.terms_version !== assignment.terms_version ||
      attempt.currency !== assignment.currency
    ) {
      throw new PaymentError(
        "RESERVATION_MISMATCH",
        "The reserved payment does not match the assignment.",
        409,
      );
    }
    if (!["PENDING", "PROCESSING"].includes(attempt.status)) {
      throw new PaymentError(
        "PAYMENT_FINAL",
        "This payment request already has a final result. Refresh status.",
        409,
      );
    }
    if (reservation.created) {
      // Never repeat this call after an unknown outcome. Bill creation has no
      // assumed idempotency header. The reservation remains PENDING on failure.
      let bill;
      try {
        bill = await this.gateway.create(attempt, assignment);
      } catch (error) {
        if (
          error instanceof PaymentError && error.code === "CHECKOUT_REJECTED"
        ) {
          await this.store.rejectCreation(attempt.payment_id, error.message);
        }
        throw error;
      }
      verifyBinding(attempt, bill);
      attempt = await this.store.attachCheckout(attempt.payment_id, bill);
    }
    if (!["PENDING", "PROCESSING"].includes(attempt.status)) {
      throw new PaymentError(
        "PAYMENT_FINAL",
        "Payment status changed during checkout creation. Check status.",
        409,
      );
    }
    if (!attempt.checkout_url) {
      throw new PaymentError(
        "PAYMENT_UNCERTAIN",
        "An existing checkout is being confirmed. Check status before retrying.",
        409,
      );
    }
    return {
      environment: "sandbox",
      assignment_id: attempt.assignment_id,
      payment_id: attempt.payment_id,
      checkout_url: attempt.checkout_url,
    };
  }
  async refresh(actor: Actor, assignmentId: string) {
    const assignment = await this.source.get(assignmentId);
    canRead(actor, assignment);
    for (const attempt of await this.store.attempts(assignmentId)) {
      if (
        !["PENDING", "PROCESSING"].includes(attempt.status) ||
        !attempt.provider_payment_id
      ) continue;
      const bill = await this.gateway.retrieve(attempt.provider_payment_id);
      verifyBinding(attempt, bill);
      await this.store.applyVerified(
        attempt.payment_id,
        bill,
        `server:${bill.id}:${bill.state}:${bill.paid}:${bill.paidAmount}`,
      );
    }
    return this.view(actor, assignment);
  }
  async webhook(request: Request) {
    const event = await this.gateway.verifyCallback(request);
    const attempt = await this.store.byId(event.paymentId);
    const bill = await this.gateway.retrieve(event.billId);
    verifyBinding(attempt, bill);
    await this.store.applyVerified(attempt.payment_id, bill, event.eventId);
  }
}

export interface PaymentApplication {
  list: PaymentService["list"];
  get: PaymentService["get"];
  forPayment: PaymentService["forPayment"];
  create: PaymentService["create"];
  refresh: PaymentService["refresh"];
  webhook: PaymentService["webhook"];
}
