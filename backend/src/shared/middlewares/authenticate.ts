import { FastifyRequest } from 'fastify';
import { UnauthorizedError } from '../errors/AppError.js';
import { AuthService } from '../../modules/auth/auth.service.js';

const authService = new AuthService();

export interface AuthenticatedUserPayload {
  sub: string;
  userId?: number;
  username?: string;
  sessionId?: string;
}

/**
 * Hook canônico de autenticação JWT com validação imediata de sessão ativa no Redis/PostgreSQL.
 * Garante revogação instantânea após logout e respostas de erro padronizadas na RFC 9457.
 */
export async function authenticateRequest(request: FastifyRequest): Promise<void> {
  try {
    await request.jwtVerify();
  } catch {
    throw new UnauthorizedError('Token de autenticação ausente, expirado ou inválido.');
  }

  const payload = request.user as AuthenticatedUserPayload | undefined;
  if (payload?.sessionId) {
    const isSessionActive = await authService.validateSession(payload.sessionId);
    if (!isSessionActive) {
      throw new UnauthorizedError('Esta sessão foi encerrada ou expirou. Faça login novamente.');
    }
  }
}

/**
 * Extrai e valida o ID numérico incremental (BIGSERIAL) do usuário autenticado na requisição.
 */
export function getAuthenticatedUserId(request: FastifyRequest): number {
  const payload = request.user as AuthenticatedUserPayload | undefined;
  const rawId = payload?.userId ?? payload?.sub;
  const numericId = Number(rawId);

  if (!numericId || Number.isNaN(numericId) || numericId <= 0) {
    throw new UnauthorizedError('Identificador de usuário inválido no token.');
  }

  return numericId;
}
