import { test, describe, before, after } from 'node:test';
import assert from 'node:assert';
import { buildApp } from './server.js';
import { FastifyInstance } from 'fastify';

describe('Testes de Contrato da API REST (RFC 9457 e Zod)', async () => {
  let app: FastifyInstance;

  before(async () => {
    app = await buildApp();
    await app.ready();
  });

  after(async () => {
    await app.close();
  });

  test('GET /health deve retornar 200 OK com status da aplicação', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/health',
    });

    assert.strictEqual(response.statusCode, 200);
    const body = JSON.parse(response.body);
    assert.strictEqual(body.status, 'ok');
    assert.ok(body.services);
  });

  test('POST /v1/auth/register com dados inválidos deve retornar 400 no padrão RFC 9457', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: {
        username: 'ab', /* Inválido (mínimo 3) */
        email: 'email-invalido',
        password: '123', /* Inválido (mínimo 8, maiúscula e número) */
      },
    });

    assert.strictEqual(response.statusCode, 400);
    assert.strictEqual(response.headers['content-type'], 'application/problem+json; charset=utf-8');

    const body = JSON.parse(response.body);
    assert.strictEqual(body.type, 'https://api.cofrinho.app/errors/validation-error');
    assert.strictEqual(body.status, 400);
    assert.strictEqual(body.code, 'VALIDATION_FAILED');
    assert.ok(body.incidentId, 'Deve conter incidentId para rastreio');
    assert.strictEqual(typeof body.timestamp, 'number', 'Timestamp deve ser numérico em epoch ms');
    assert.ok(Array.isArray(body.invalidParams));
    assert.ok(body.invalidParams.length > 0);
  });

  test('POST /v1/auth/login sem payload deve retornar 400 no formato RFC 9457', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: {},
    });

    assert.strictEqual(response.statusCode, 400);
    assert.strictEqual(response.headers['content-type'], 'application/problem+json; charset=utf-8');

    const body = JSON.parse(response.body);
    assert.strictEqual(body.status, 400);
    assert.strictEqual(body.code, 'VALIDATION_FAILED');
    assert.ok(body.incidentId);
    assert.strictEqual(typeof body.timestamp, 'number');
  });

  test('GET /v1/users/me sem token JWT deve retornar 401 Unauthorized', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/v1/users/me',
    });

    assert.strictEqual(response.statusCode, 401);
    assert.strictEqual(response.headers['content-type'], 'application/problem+json; charset=utf-8');

    const body = JSON.parse(response.body);
    assert.strictEqual(body.type, 'https://api.cofrinho.app/errors/unauthorized');
    assert.strictEqual(body.status, 401);
    assert.strictEqual(body.code, 'UNAUTHORIZED');
    assert.ok(body.incidentId);
    assert.strictEqual(typeof body.timestamp, 'number');
  });
});

