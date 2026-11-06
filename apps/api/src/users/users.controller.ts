import { Body, Controller, Get, Header, Patch, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator.js';
import type { AuthenticatedUser } from '../common/security/authenticated-user.js';
import { CsrfGuard } from '../common/security/csrf.guard.js';
import { SessionAuthGuard } from '../common/security/session-auth.guard.js';
import { UpdateProfileDto } from './dto/update-profile.dto.js';
import { UsersService } from './users.service.js';

@Controller('users')
@UseGuards(SessionAuthGuard, CsrfGuard)
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  @Header('Cache-Control', 'no-store')
  me(@CurrentUser() user: AuthenticatedUser): AuthenticatedUser {
    return user;
  }

  @Patch('me')
  @Header('Cache-Control', 'no-store')
  updateMe(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateProfileDto,
  ): Promise<AuthenticatedUser> {
    return this.users.updateProfile(user.id, dto);
  }
}
