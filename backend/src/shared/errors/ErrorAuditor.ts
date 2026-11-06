import crypto from 'crypto';
import { dbPool } from '../../database/postgres.js';
import { AppError } from './AppError.js';

export interface AuditLogOptions {
  userId?: number;
  statusCode?: number;
  code?: string;
  contextData?: Record<string, unknown>;
  requestUrl?: string;
  method?: string;
}

/**
 * Serviço de auditoria centralizada de erros e incidentes para o Cofrinho.
 * Persiste rastreamento de falhas na tabela `log_errors` em PostgreSQL
 * com timestamps numéricos (epoch ms) e identificador de incidente (incidentId).
 */
export class ErrorAuditor {
  private static isAuditing = false;

  /**
   * Registra um incidente no PostgreSQL de forma segura e não-bloqueante.
   * Retorna o identificador único do incidente gerado.
   */
  public static async log(error: unknown, options: AuditLogOptions = {}): Promise<string> {
    const isAppErr = error instanceof AppError;
    const incidentId = isAppErr ? error.incidentId : crypto.randomUUID();
    const statusCode = isAppErr ? error.statusCode : (options.statusCode || 500);
    const code = isAppErr ? error.code : (options.code || 'INTERNAL_ERROR');

    const errObj = error instanceof Error ? error : new Error(String(error));
    const message = errObj.message || 'Erro não especificado';
    const trace = errObj.stack || String(error);

    /* Previne recursão infinita caso a persistência falhe */
    if (this.isAuditing) {
      console.error(`[ErrorAuditor] [${incidentId}] Falha durante auditoria recursiva:`, message);
      return incidentId;
    }

    try {
      this.isAuditing = true;

      const contextPayload: Record<string, unknown> = {
        ...(options.contextData || {}),
        requestUrl: options.requestUrl,
        method: options.method,
      };

      if (isAppErr && error.context) {
        contextPayload.errorContext = error.context;
      }

      const insertSql = `
        INSERT INTO log_errors (
          incident_id, user_id, message, code, status_code, error_trace, context_data, timestamp, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, 'OPEN')
      `;

      const targetUserId = options.userId && options.userId > 0 ? options.userId : null;
      const nowTimestamp = Date.now();

      try {
        await dbPool.query(insertSql, [
          incidentId,
          targetUserId,
          message,
          code,
          statusCode,
          trace,
          JSON.stringify(contextPayload),
          nowTimestamp,
        ]);
      } catch (dbErr: any) {
        /* Se houver falha de chave estrangeira (usuário não encontrado), tenta gravar sem user_id */
        if (targetUserId && (dbErr?.code === '23503' || dbErr?.message?.includes('violates foreign key'))) {
          await dbPool.query(insertSql, [
            incidentId,
            null,
            message,
            code,
            statusCode,
            trace,
            JSON.stringify(contextPayload),
            nowTimestamp,
          ]);
        } else {
          console.warn(`⚠️ [ErrorAuditor] Falha ao persistir erro no PostgreSQL:`, dbErr.message);
        }
      }
    } catch (e: any) {
      console.warn(`⚠️ [ErrorAuditor] Erro inesperado no appender:`, e.message);
    } finally {
      this.isAuditing = false;
    }

    return incidentId;
  }
}

