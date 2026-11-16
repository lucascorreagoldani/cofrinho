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

  test('Rotas protegidas (/v1/categories, /v1/accounts, /v1/transactions) sem token devem retornar 401 RFC 9457 unificado', async () => {
    const protectedRoutes = ['/v1/categories', '/v1/accounts', '/v1/transactions'];
    const incidentIds = new Set<string>();

    for (const url of protectedRoutes) {
      const response = await app.inject({
        method: 'GET',
        url,
      });

      assert.strictEqual(response.statusCode, 401, `Rota ${url} deve retornar 401`);
      assert.strictEqual(response.headers['content-type'], 'application/problem+json; charset=utf-8');

      const body = JSON.parse(response.body);
      assert.strictEqual(body.type, 'https://api.cofrinho.app/errors/unauthorized');
      assert.strictEqual(body.status, 401);
      assert.strictEqual(body.code, 'UNAUTHORIZED');
      assert.ok(body.incidentId && body.incidentId !== 'incident_jwt_required', 'incidentId deve ser um UUID dinâmico');
      assert.strictEqual(typeof body.timestamp, 'number');
      incidentIds.add(body.incidentId);
    }

    assert.strictEqual(incidentIds.size, protectedRoutes.length, 'Cada falha 401 deve gerar um incidentId exclusivo');
  });

  test('Rota protegida com token JWT inválido deve retornar 401 no formato RFC 9457', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/v1/transactions',
      headers: {
        authorization: 'Bearer token.invalido.aqui',
      },
    });

    assert.strictEqual(response.statusCode, 401);
    assert.strictEqual(response.headers['content-type'], 'application/problem+json; charset=utf-8');
    const body = JSON.parse(response.body);
    assert.strictEqual(body.code, 'UNAUTHORIZED');
    assert.ok(body.incidentId);
  });

  test('Rotas públicas (/v1/public/time e /v1/public/enums) devem responder 200 sem JWT', async () => {
    const timeRes = await app.inject({
      method: 'GET',
      url: '/v1/public/time',
    });
    assert.strictEqual(timeRes.statusCode, 200);
    const timeBody = JSON.parse(timeRes.body);
    assert.strictEqual(typeof timeBody.timestamp, 'number');

    const enumsRes = await app.inject({
      method: 'GET',
      url: '/v1/public/enums',
    });
    assert.strictEqual(enumsRes.statusCode, 200);
    const enumsBody = JSON.parse(enumsRes.body);
    assert.ok(Array.isArray(enumsBody.enums.account_type));
    assert.ok(Array.isArray(enumsBody.defaults.categories));
  });
});

