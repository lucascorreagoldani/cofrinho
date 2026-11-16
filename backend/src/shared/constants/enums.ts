import { z } from 'zod';

/**
 * Enums canônicos de domínio compartilhados entre esquemas Zod, serviços e banco de dados PostgreSQL.
 */

export enum RecordStatus {
  ACTIVE = 'active',
  HIDDEN = 'hidden',
  DELETED = 'deleted',
}

export enum TransactionFilterStatus {
  ACTIVE = 'active',
  HIDDEN = 'hidden',
  ALL = 'all',
  DELETED = 'deleted',
}

export enum TransactionType {
  EXPENSE = 'expense',
  INCOME = 'income',
}

export enum AccountType {
  CREDIT_CARD = 'credit_card',
  BANK_ACCOUNT = 'bank_account',
  WALLET = 'wallet',
  PIX = 'pix',
  CASH = 'cash',
}

export enum DeleteCascadeMode {
  SINGLE = 'single',
  ALL_FUTURE = 'all_future',
}

export enum SessionStatus {
  ACTIVE = 'active',
  EXPIRED = 'expired',
  REVOKED = 'revoked',
}

export enum ErrorLogStatus {
  OPEN = 'OPEN',
  RESOLVED = 'RESOLVED',
  IGNORED = 'IGNORED',
}

export const recordStatusSchema = z.nativeEnum(RecordStatus);
export const transactionFilterStatusSchema = z.nativeEnum(TransactionFilterStatus);
export const transactionTypeSchema = z.nativeEnum(TransactionType);
export const accountTypeSchema = z.nativeEnum(AccountType);
export const deleteCascadeModeSchema = z.nativeEnum(DeleteCascadeMode);
export const sessionStatusSchema = z.nativeEnum(SessionStatus);
