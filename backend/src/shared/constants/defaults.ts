/**
 * Categorias e Contas Canônicas padrão para inicialização de novas contas de usuário.
 */

export interface DefaultCategory {
  name: string;
  icon: string;
  color: string;
}

export interface DefaultAccount {
  name: string;
  type: 'credit_card' | 'bank_account' | 'wallet' | 'pix' | 'cash';
  icon: string;
  color: string;
  allows_installments: boolean;
  closing_day?: number;
  due_day?: number;
}

export const CANONICAL_CATEGORIES: readonly DefaultCategory[] = [
  { name: 'Alimentação', icon: 'fork.knife', color: '#FF9500' },
  { name: 'Transporte', icon: 'car.fill', color: '#007AFF' },
  { name: 'Lazer', icon: 'sparkles', color: '#AF52DE' },
  { name: 'Saúde', icon: 'heart.fill', color: '#FF2D55' },
  { name: 'Educação', icon: 'book.fill', color: '#34C759' },
  { name: 'Outros', icon: 'ellipsis.circle.fill', color: '#8E8E93' },
] as const;

export const CANONICAL_ACCOUNTS: readonly DefaultAccount[] = [
  {
    name: 'Cartão de Crédito',
    type: 'credit_card',
    icon: 'creditcard.fill',
    color: '#5856D6',
    allows_installments: true,
    closing_day: 20,
    due_day: 27,
  },
  {
    name: 'PIX',
    type: 'pix',
    icon: 'bolt.fill',
    color: '#00C7BE',
    allows_installments: false,
  },
  {
    name: 'Dinheiro',
    type: 'cash',
    icon: 'banknote.fill',
    color: '#34C759',
    allows_installments: false,
  },
] as const;

