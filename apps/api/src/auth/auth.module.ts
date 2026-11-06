import { Module } from '@nestjs/common';
import { CsrfGuard } from '../common/security/csrf.guard.js';
import { SessionAuthGuard } from '../common/security/session-auth.guard.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { PasswordService } from './password.service.js';

@Module({
  controllers: [AuthController],
  providers: [AuthService, PasswordService, CsrfGuard, SessionAuthGuard],
  exports: [AuthService, CsrfGuard, SessionAuthGuard],
})
export class AuthModule {}
