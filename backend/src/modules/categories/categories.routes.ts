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
import { authenticateRequest, getAuthenticatedUserId } from '../../shared/middlewares/authenticate.js';

const categoriesService = new CategoriesService();

export const categoriesRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Hook canônico de autenticação JWT + validação de sessão no Redis/PostgreSQL */
  app.addHook('onRequest', authenticateRequest);

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
      const userId = getAuthenticatedUserId(request);
      const categories = await categoriesService.listCategories(
        userId,
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
          401: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const category = await categoriesService.createCategory(userId, request.body);
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
          401: problemDetailsSchema,
          404: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const updated = await categoriesService.updateCategory(
        userId,
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
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      await categoriesService.deleteCategory(userId, request.params.id);
      return reply.status(204).send(null);
    }
  );
};

