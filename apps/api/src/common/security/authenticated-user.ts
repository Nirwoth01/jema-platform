export interface AuthenticatedUser {
  id: string;
  firstName: string;
  lastName: string | null;
  email: string | null;
  phoneE164: string | null;
  preferredLanguageCode: 'fr' | 'en';
  accountStatus: 'pending' | 'active' | 'suspended' | 'closed';
  emailVerifiedAt: string | null;
  phoneVerifiedAt: string | null;
  createdAt: string;
  roles: string[];
}
