import { Transform } from 'class-transformer';
import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

const trimString = ({ value }: { value: unknown }): unknown =>
  typeof value === 'string' ? value.trim() : value;

export class RegisterDto {
  @Transform(trimString)
  @IsString()
  @MinLength(1)
  @MaxLength(80)
  firstName!: string;

  @Transform(trimString)
  @IsOptional()
  @IsString()
  @MaxLength(80)
  lastName?: string;

  @Transform(trimString)
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  email?: string;

  @Transform(trimString)
  @IsOptional()
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, { message: 'phoneE164 doit être au format international, par exemple +243…' })
  phoneE164?: string;

  @IsString()
  @MinLength(12)
  @MaxLength(128)
  password!: string;

  @IsOptional()
  @IsIn(['fr', 'en'])
  preferredLanguageCode?: 'fr' | 'en';

  @IsOptional()
  @IsIn(['email', 'sms'])
  verificationChannel?: 'email' | 'sms';
}

export class LoginDto {
  @Transform(trimString)
  @IsString()
  @MinLength(3)
  @MaxLength(254)
  identifier!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;
}

export class VerifyCodeDto {
  @Transform(trimString)
  @IsString()
  @MinLength(3)
  @MaxLength(254)
  identifier!: string;

  @Transform(trimString)
  @IsString()
  @Matches(/^\d{6}$/, { message: 'Le code de vérification doit contenir 6 chiffres.' })
  code!: string;
}

export class ForgotPasswordDto {
  @Transform(trimString)
  @IsString()
  @MinLength(3)
  @MaxLength(254)
  identifier!: string;
}

export class ResetPasswordDto {
  @Transform(trimString)
  @IsString()
  @MinLength(3)
  @MaxLength(254)
  identifier!: string;

  @Transform(trimString)
  @IsString()
  @MinLength(32)
  @MaxLength(128)
  token!: string;

  @IsString()
  @MinLength(12)
  @MaxLength(128)
  newPassword!: string;
}
