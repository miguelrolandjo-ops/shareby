import { ApiError, ApiUnreachable } from '../data/api';
import { UserError } from '../data/repository';

/** Sentences a person can act on. */
export function friendlyError(e: unknown): string {
  if (e instanceof ApiUnreachable || e instanceof UserError || e instanceof ApiError) return e.message;
  return 'Something went wrong. Please try again.';
}
