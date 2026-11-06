import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const request = context.getRequest<Request>();
    const response = context.getResponse<Response>();
    const statusCode = exception instanceof HttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    if (!(exception instanceof HttpException)) {
      this.logger.error(`Erreur interne pour la requête ${response.locals.requestId ?? 'inconnue'}.`);
    }

    const exceptionPayload = exception instanceof HttpException ? exception.getResponse() : undefined;
    const payloadMessage = typeof exceptionPayload === 'object' && exceptionPayload !== null && 'message' in exceptionPayload
      ? exceptionPayload.message
      : exceptionPayload;
    const message = statusCode >= 500
      ? 'Une erreur interne est survenue.'
      : typeof payloadMessage === 'string' || (
        Array.isArray(payloadMessage) && payloadMessage.every((item) => typeof item === 'string')
      )
        ? payloadMessage
        : 'La requête ne peut pas être traitée.';

    response.status(statusCode).json({
      statusCode,
      error: statusCode >= 500 ? 'Erreur interne' : 'Requête invalide',
      message,
      timestamp: new Date().toISOString(),
      path: request.originalUrl,
      requestId: response.locals.requestId ?? null,
    });
  }
}
