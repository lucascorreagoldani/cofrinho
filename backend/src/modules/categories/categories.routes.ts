import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { CategoriesService } from './categories.service.js';
import {
  categoryResponseSchema,
  createCategoryBodySchema,
  updateCategoryBodySchema,
  listCategoriesQuerySchema,
} from './categories.schemas.js';
import { problemDetailsSchema } from '../auth/auth.schemas.js';

const categoriesService = new CategoriesService();

export const categoriesRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Hook de Autenticação JWT */
  app.addHook('onRequest', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch (err) {
      return reply.status(401).send({
        type: 'https://cofrinho.app/errors/unauthorized',
        title: 'Não Autorizado',
        status: 401,
        detail: 'Token de autenticação ausente ou expirado.',
        code: 'AUTH_001',
        incidentId: 'incident_jwt_required',
        timestamp: Date.now(),
      });
    }
  });

  /* 1. GET /v1/categories - Listar categorias */
  app.get(
    '',
    {
      schema: {
        tags: ['Categorias'],
        summary: 'Listar categorias do usuário',
        querystring: listCategoriesQuerySchema,
        response: {
          200: z.array(categoryResponseSchema),
          401: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const categories = await categoriesService.listCategories(
        userPayload.userId,
        request.query.include_hidden
      );
      return reply.status(200).send(categories);
    }
  );

  /* 2. POST /v1/categories - Criar categoria */
  app.post(
    '',
    {
      schema: {
        tags: ['Categorias'],
        summary: 'Criar nova categoria personalizada',
        body: createCategoryBodySchema,
        response: {
          201: categoryResponseSchema,
          400: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const category = await categoriesService.createCategory(userPayload.userId, request.body);
      return reply.status(201).send(category);
    }
  );

  /* 3. PUT /v1/categories/:id - Atualizar categoria */
  app.put(
    '/:id',
    {
      schema: {
        tags: ['Categorias'],
        summary: 'Atualizar categoria existente',
        params: z.object({ id: z.coerce.number().int().positive() }),
        body: updateCategoryBodySchema,
        response: {
          200: categoryResponseSchema,
          404: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const updated = await categoriesService.updateCategory(
        userPayload.userId,
        request.params.id,
        request.body
      );
      return reply.status(200).send(updated);
    }
  );

  /* 4. DELETE /v1/categories/:id - Excluir categoria (soft delete) */
  app.delete(
    '/:id',
    {
      schema: {
        tags: ['Categorias'],
        summary: 'Excluir categoria (soft delete)',
        params: z.object({ id: z.coerce.number().int().positive() }),
        response: {
          204: z.null(),
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      await categoriesService.deleteCategory(userPayload.userId, request.params.id);
      return reply.status(204).send(null);
    }
  );
};

