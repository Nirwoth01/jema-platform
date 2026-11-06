import type { Request, Response } from 'express';
import { env } from '../../config/env.js';

const securePrefix = env.NODE_ENV === 'production' ? '__Host-' : '';

export const sessionCookieName = `${securePrefix}jema_session`;
export const csrfCookieName = `${securePrefix}jema_csrf`;

function appendCookie(response: Response, value: string): void {
  response.append('Set-Cookie', value);
}

function cookieOptions(httpOnly: boolean, maxAgeSeconds: number): string {
  const parts = [
    'Path=/',
    `Max-Age=${maxAgeSeconds}`,
    'SameSite=Strict',
  ];

  if (httpOnly) parts.push('HttpOnly');
  if (env.NODE_ENV === 'production') parts.push('Secure');
  return parts.join('; ');
}

export function setSessionCookie(response: Response, token: string): void {
  const maxAgeSeconds = env.AUTH_SESSION_TTL_HOURS * 60 * 60;
  appendCookie(response, `${sessionCookieName}=${encodeURIComponent(token)}; ${cookieOptions(true, maxAgeSeconds)}`);
}

export function clearSessionCookie(response: Response): void {
  appendCookie(response, `${sessionCookieName}=; ${cookieOptions(true, 0)}; Expires=Thu, 01 Jan 1970 00:00:00 GMT`);
}

export function setCsrfCookie(response: Response, token: string): void {
  appendCookie(response, `${csrfCookieName}=${encodeURIComponent(token)}; ${cookieOptions(false, 60 * 60 * 24)}`);
}

export function readCookie(request: Request, name: string): string | undefined {
  const header = request.headers.cookie;
  if (!header) return undefined;

  for (const cookie of header.split(';')) {
    const separator = cookie.indexOf('=');
    if (separator < 0 || cookie.slice(0, separator).trim() !== name) continue;
    const value = cookie.slice(separator + 1).trim();

    try {
      return decodeURIComponent(value);
    } catch {
      return undefined;
    }
  }

  return undefined;
}
