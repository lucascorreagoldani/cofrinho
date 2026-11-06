import crypto from 'crypto';

export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail: string;
  instance?: string;
  code: string;
  incidentId: string;
  timestamp: number;
  invalidParams?: Array<{ name: string; reason: string }>;
  context?: Record<string, unknown>;
}

export interface AppErrorOptions {
  code?: string;
  type?: string;
  context?: Record<string, unknown>;
  invalidParams?: Array<{ name: string; reason: string }>;
  cause?: Error;
}

/**
 * Classe base canônica para exceções da aplicação Cofrinho.
 * Implementa conformidade estrita com RFC 9457 (Problem Details for HTTP APIs)
 * com rastreabilidade por incidentId e timestamps numéricos (epoch ms).
 */
export class AppError extends Error {
  public readonly incidentId: string;
  public readonly statusCode: number;
  public readonly code: string;
  public readonly type: string;
  public readonly detail: string;
  public readonly timestamp: number;
  public readonly context?: Record<string, unknown>;
  public readonly invalidParams?: Array<{ name: string; reason: string }>;

  constructor(
    title: string,
    detail: string,
    statusCode = 400,
    options: AppErrorOptions = {}
  ) {
    super(title);
    this.name = this.constructor.name;
    this.statusCode = statusCode;
    this.detail = detail;
    this.incidentId = crypto.randomUUID();
    this.timestamp = Date.now();
    this.code = options.code || 'BAD_REQUEST';
    this.type = options.type || 'https://api.cofrinho.app/errors/bad-request';
    this.context = options.context;
    this.invalidParams = options.invalidParams;

    if (options.cause) {
      this.cause = options.cause;
    }

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

  public toProblemDetails(instance?: string): ProblemDetails {
    return {
      type: this.type,
      title: this.message,
      status: this.statusCode,
      detail: this.detail,
      instance,
      code: this.code,
      incidentId: this.incidentId,
      timestamp: this.timestamp,
      invalidParams: this.invalidParams,
      context: this.context,
    };
  }
}

/**
 * Erro 400: Falha de validação de payload ou parâmetros.
 */
export class ValidationError extends AppError {
  constructor(
    detail = 'Um ou mais campos não atenderam aos critérios exigidos.',
    invalidParams?: Array<{ name: string; reason: string }>
  ) {
    super('Erro de Validação', detail, 400, {
      code: 'VALIDATION_FAILED',
      type: 'https://api.cofrinho.app/errors/validation-error',
      invalidParams,
    });
  }
}

/**
 * Erro 401: Falha de autenticação ou token JWT ausente/expirado.
 */
export class UnauthorizedError extends AppError {
  constructor(detail = 'Token de autenticação ausente, expirado ou inválido.') {
    super('Não Autorizado', detail, 401, {
      code: 'UNAUTHORIZED',
      type: 'https://api.cofrinho.app/errors/unauthorized',
    });
  }
}

/**
 * Erro 403: Acesso negado por permissões insuficientes.
 */
export class ForbiddenError extends AppError {
  constructor(detail = 'Você não possui permissão para acessar este recurso.') {
    super('Acesso Proibido', detail, 403, {
      code: 'FORBIDDEN',
      type: 'https://api.cofrinho.app/errors/forbidden',
    });
  }
}

/**
 * Erro 404: Recurso solicitado não encontrado.
 */
export class NotFoundError extends AppError {
  constructor(detail = 'O recurso solicitado não foi encontrado.') {
    super('Não Encontrado', detail, 404, {
      code: 'NOT_FOUND',
      type: 'https://api.cofrinho.app/errors/not-found',
    });
  }
}

/**
 * Erro 409: Conflito de identificador único (username, email, etc.).
 */
export class ConflictError extends AppError {
  constructor(detail = 'Já existe um recurso com os identificadores fornecidos.') {
    super('Conflito de Recurso', detail, 409, {
      code: 'RESOURCE_CONFLICT',
      type: 'https://api.cofrinho.app/errors/conflict',
    });
  }
}

/**
 * Erro 429: Limite de taxa de requisições excedido.
 */
export class RateLimitError extends AppError {
  constructor(detail = 'Limite de requisições excedido. Aguarde antes de tentar novamente.') {
    super('Muitas Requisições', detail, 429, {
      code: 'RATE_LIMIT_EXCEEDED',
      type: 'https://api.cofrinho.app/errors/rate-limit',
    });
  }
}

/**
 * Erro 500: Falha interna de persistência ou consulta no banco de dados.
 */
export class DatabaseError extends AppError {
  constructor(detail = 'Falha de comunicação ou operação no banco de dados.', cause?: Error) {
    super('Erro de Banco de Dados', detail, 500, {
      code: 'DATABASE_ERROR',
      type: 'https://api.cofrinho.app/errors/database-error',
      cause,
    });
  }
}

/**
 * Erro 500: Falha inesperada do servidor.
 */
export class InternalError extends AppError {
  constructor(detail = 'Ocorreu um erro interno inesperado no servidor.', cause?: Error) {
    super('Erro Interno do Servidor', detail, 500, {
      code: 'INTERNAL_ERROR',
      type: 'https://api.cofrinho.app/errors/internal-server-error',
      cause,
    });
  }
}

/**
 * Erro 503: Serviço temporariamente indisponível (Redis, DB, etc.).
 */
export class ServiceUnavailableError extends AppError {
  constructor(detail = 'Serviço temporariamente indisponível. Tente novamente em instantes.') {
    super('Serviço Indisponível', detail, 503, {
      code: 'SERVICE_UNAVAILABLE',
      type: 'https://api.cofrinho.app/errors/service-unavailable',
    });
  }
}
