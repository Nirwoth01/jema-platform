import { timingSafeEqual } from 'node:crypto';
import { CanActivate, ExecutionContext, Injectable, ForbiddenException } from '@nestjs/common';
import type { Request } from 'express';
import { csrfCookieName, readCookie } from './cookies.js';

@Injectable()
export class CsrfGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return true;

    const cookieToken = readCookie(request, csrfCookieName);
    const headerToken = request.headers['x-csrf-token'];
    if (!cookieToken || typeof headerToken !== 'string' || cookieToken.length > 128 || headerToken.length > 128) {
      throw new ForbiddenException('Jeton CSRF manquant. Rechargez le jeton de sécurité.');
    }

    const cookieBuffer = Buffer.from(cookieToken);
    const headerBuffer = Buffer.from(headerToken);
    if (cookieBuffer.length !== headerBuffer.length || !timingSafeEqual(cookieBuffer, headerBuffer)) {
      throw new ForbiddenException('Jeton CSRF invalide.');
    }

    return true;
  }
}
