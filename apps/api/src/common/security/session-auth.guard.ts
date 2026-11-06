import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from '../../auth/auth.service.js';
import { sessionCookieName, readCookie } from './cookies.js';

@Injectable()
export class SessionAuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: unknown }>();
    const token = readCookie(request, sessionCookieName);
    if (!token) throw new UnauthorizedException('Authentification requise.');

    const user = await this.auth.findAuthenticatedSession(token);
    if (!user) throw new UnauthorizedException('Session invalide ou expirée.');
    request.user = user;
    return true;
  }
}
