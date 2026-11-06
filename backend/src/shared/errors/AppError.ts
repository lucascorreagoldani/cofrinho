export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail: string;
  instance?: string;
  code: string;
  invalidParams?: Array<{ name: string; reason: string }>;
}

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly type: string;
  public readonly detail: string;
  public readonly invalidParams?: Array<{ name: string; reason: string }>;

  constructor(
    title: string,
    detail: string,
    statusCode = 400,
    code = 'BAD_REQUEST',
    type = 'https://api.cofrinho.app/errors/bad-request',
    invalidParams?: Array<{ name: string; reason: string }>
  ) {
    super(title);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.type = type;
    this.detail = detail;
    this.invalidParams = invalidParams;
  }

  public toProblemDetails(instance?: string): ProblemDetails {
    return {
      type: this.type,
      title: this.message,
      status: this.statusCode,
      detail: this.detail,
      instance,
      code: this.code,
      invalidParams: this.invalidParams,
    };
  }
}

