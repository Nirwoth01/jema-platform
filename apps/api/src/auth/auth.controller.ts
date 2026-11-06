import { randomBytes } from 'node:crypto';
import {
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { CsrfGuard } from '../common/security/csrf.guard.js';
import {
  clearSessionCookie,
  readCookie,
  setCsrfCookie,
  setSessionCookie,
  sessionCookieName,
} from '../common/security/cookies.js';
import {
  ForgotPasswordDto,
  LoginDto,
  RegisterDto,
  ResetPasswordDto,
  VerifyCodeDto,
} from './dto/auth.dto.js';
import { AuthService } from './auth.service.js';

@Controller('auth')
@UseGuards(CsrfGuard)
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Get('csrf')
  @Header('Cache-Control', 'no-store')
  csrf(@Res({ passthrough: true }) response: Response) {
    const token = randomBytes(32).toString('base64url');
    setCsrfCookie(response, token);
    response.setHeader('Cache-Control', 'no-store');
    return { csrfToken: token };
  }

  @Post('register')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Post('verify')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  async verify(
    @Body() dto: VerifyCodeDto,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const { user, sessionToken } = await this.auth.verifySignupCode(dto, this.userAgent(request));
    setSessionCookie(response, sessionToken);
    response.setHeader('Cache-Control', 'no-store');
    return { user };
  }

  @Post('verification/resend')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  resendVerification(@Body() dto: ForgotPasswordDto) {
    return this.auth.resendSignupCode(dto.identifier);
  }

  @Post('login')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  async login(
    @Body() dto: LoginDto,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const { user, sessionToken } = await this.auth.login(dto, this.userAgent(request));
    setSessionCookie(response, sessionToken);
    response.setHeader('Cache-Control', 'no-store');
    return { user };
  }

  @Post('logout')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  async logout(@Req() request: Request, @Res({ passthrough: true }) response: Response) {
    await this.auth.logout(readCookie(request, sessionCookieName));
    clearSessionCookie(response);
    response.setHeader('Cache-Control', 'no-store');
    return { loggedOut: true };
  }

  @Post('password/forgot')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.auth.requestPasswordReset(dto);
  }

  @Post('password/reset')
  @Header('Cache-Control', 'no-store')
  @HttpCode(HttpStatus.OK)
  async resetPassword(
    @Body() dto: ResetPasswordDto,
    @Res({ passthrough: true }) response: Response,
  ) {
    const result = await this.auth.resetPassword(dto);
    clearSessionCookie(response);
    response.setHeader('Cache-Control', 'no-store');
    return result;
  }

  private userAgent(request: Request): string | undefined {
    const value = request.headers['user-agent'];
    return typeof value === 'string' ? value : undefined;
  }
}
