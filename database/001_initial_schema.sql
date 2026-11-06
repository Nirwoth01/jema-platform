-- Jema V1 / PostgreSQL 18
-- Initialisation d'une base vide. À exécuter une seule fois.
-- Les montants utilisent NUMERIC, jamais FLOAT. Aucun taux de commission n'est activé par défaut.
-- Les mots de passe, tokens, secrets opérateurs et données de paiement ne sont jamais stockés en clair.

BEGIN;
SET TIME ZONE 'UTC';

CREATE TABLE languages (
  code varchar(5) PRIMARY KEY, name text NOT NULL, is_active boolean NOT NULL DEFAULT true
);
INSERT INTO languages(code,name) VALUES ('fr','Français'),('en','English');

CREATE TABLE currencies (
  code char(3) PRIMARY KEY, name text NOT NULL,
  minor_units smallint NOT NULL CHECK (minor_units BETWEEN 0 AND 4),
  is_active boolean NOT NULL DEFAULT true
);
INSERT INTO currencies(code,name,minor_units) VALUES ('CDF','Franc congolais',0),('USD','Dollar américain',2);

CREATE TABLE locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id uuid REFERENCES locations(id) ON DELETE RESTRICT,
  country_code char(2) NOT NULL DEFAULT 'CD',
  location_type varchar(16) NOT NULL CHECK(location_type IN ('country','province','city','territory','commune','zone')),
  name text NOT NULL, slug text NOT NULL, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT(country_code,parent_id,location_type,slug)
);
CREATE INDEX idx_locations_parent ON locations(parent_id);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name text NOT NULL, last_name text, email text, phone_e164 varchar(20),
  password_hash text NOT NULL,
  preferred_language_code varchar(5) NOT NULL DEFAULT 'fr' REFERENCES languages(code),
  account_status varchar(16) NOT NULL DEFAULT 'pending'
    CHECK(account_status IN ('pending','active','suspended','closed')),
  email_verified_at timestamptz, phone_verified_at timestamptz,
  mfa_enabled boolean NOT NULL DEFAULT false, last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, CHECK(email IS NOT NULL OR phone_e164 IS NOT NULL)
);
CREATE UNIQUE INDEX uq_users_email ON users(lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX uq_users_phone ON users(phone_e164) WHERE phone_e164 IS NOT NULL;
CREATE INDEX idx_users_status_page ON users(account_status,created_at DESC,id DESC);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code varchar(40) NOT NULL UNIQUE,
  name text NOT NULL, description text, is_system_role boolean NOT NULL DEFAULT false
);
INSERT INTO roles(code,name,is_system_role) VALUES
 ('buyer','Acheteur',true),('seller','Vendeur',true),('jema_agent','Agent Jema',true),
 ('finance','Finance',true),('moderator','Modérateur',true),('administrator','Administrateur',true);

CREATE TABLE permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code varchar(100) NOT NULL UNIQUE, description text
);
CREATE TABLE role_permissions (
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY(role_id,permission_id)
);
CREATE TABLE user_roles (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  granted_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,role_id)
);
CREATE INDEX idx_user_roles_role ON user_roles(role_id,user_id);

CREATE TABLE user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE, user_agent text, ip_address inet,
  created_at timestamptz NOT NULL DEFAULT now(), last_seen_at timestamptz,
  expires_at timestamptz NOT NULL, revoked_at timestamptz, CHECK(expires_at>created_at)
);
CREATE INDEX idx_sessions_active ON user_sessions(user_id,expires_at DESC) WHERE revoked_at IS NULL;

CREATE TABLE password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL, consumed_at timestamptz, CHECK(expires_at>created_at)
);
CREATE INDEX idx_password_reset_user ON password_reset_tokens(user_id,expires_at DESC);

CREATE TABLE verification_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  channel varchar(8) NOT NULL CHECK(channel IN ('email','sms')),
  purpose varchar(24) NOT NULL CHECK(purpose IN ('signup','login','password_reset','change_contact')),
  destination text NOT NULL, token_hash text NOT NULL, attempts smallint NOT NULL DEFAULT 0 CHECK(attempts>=0),
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  consumed_at timestamptz, CHECK(expires_at>created_at)
);
CREATE INDEX idx_challenges_open ON verification_challenges(destination,purpose,expires_at DESC) WHERE consumed_at IS NULL;

CREATE TABLE user_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label text NOT NULL, recipient_name text NOT NULL, phone_e164 varchar(20) NOT NULL,
  location_id uuid REFERENCES locations(id) ON DELETE SET NULL,
  address_line text NOT NULL, additional_details text, latitude numeric(9,6), longitude numeric(9,6),
  is_default boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL)),
  CHECK(latitude IS NULL OR latitude BETWEEN -90 AND 90),
  CHECK(longitude IS NULL OR longitude BETWEEN -180 AND 180)
);
CREATE INDEX idx_addresses_user ON user_addresses(user_id,created_at DESC);
CREATE UNIQUE INDEX uq_user_default_address ON user_addresses(user_id) WHERE is_default;

CREATE TABLE file_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  storage_provider varchar(30) NOT NULL, storage_bucket text NOT NULL, storage_key text NOT NULL,
  original_filename text NOT NULL, mime_type text NOT NULL, file_size_bytes bigint NOT NULL CHECK(file_size_bytes>0),
  sha256_hex char(64), access_scope varchar(8) NOT NULL DEFAULT 'private' CHECK(access_scope IN ('private','public')),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(storage_bucket,storage_key)
);
CREATE INDEX idx_file_assets_owner ON file_assets(owner_user_id,created_at DESC);

CREATE TABLE seller_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES users(id) ON DELETE RESTRICT,
  seller_type varchar(10) NOT NULL CHECK(seller_type IN ('merchant','platform')),
  display_name text NOT NULL, slug text NOT NULL UNIQUE, description text,
  location_id uuid REFERENCES locations(id) ON DELETE SET NULL,
  default_currency_code char(3) NOT NULL DEFAULT 'CDF' REFERENCES currencies(code),
  profile_status varchar(16) NOT NULL DEFAULT 'pending' CHECK(profile_status IN ('pending','active','suspended','closed')),
  verification_status varchar(16) NOT NULL DEFAULT 'not_started'
    CHECK(verification_status IN ('not_started','pending','verified','rejected','expired')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((seller_type='merchant' AND owner_user_id IS NOT NULL) OR (seller_type='platform' AND owner_user_id IS NULL))
);
CREATE UNIQUE INDEX uq_seller_owner ON seller_profiles(owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX idx_sellers_status ON seller_profiles(profile_status,verification_status);
INSERT INTO seller_profiles(seller_type,display_name,slug,profile_status,verification_status)
VALUES('platform','Jema','jema','active','verified');

CREATE TABLE seller_verification_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  submitted_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  assigned_to_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  status varchar(20) NOT NULL DEFAULT 'submitted'
    CHECK(status IN ('submitted','in_review','approved','rejected','needs_information','closed')),
  reviewer_note text, submitted_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX idx_seller_verification_queue ON seller_verification_cases(status,submitted_at);

CREATE TABLE seller_verification_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES seller_verification_cases(id) ON DELETE CASCADE,
  file_asset_id uuid NOT NULL REFERENCES file_assets(id) ON DELETE RESTRICT,
  document_type varchar(40) NOT NULL, review_status varchar(12) NOT NULL DEFAULT 'pending'
    CHECK(review_status IN ('pending','approved','rejected')),
  reviewed_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL, reviewed_at timestamptz,
  UNIQUE(case_id,file_asset_id)
);

CREATE TABLE seller_payout_destinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  provider_code varchar(16) NOT NULL CHECK(provider_code IN ('mpesa','airtel_money','orange_money')),
  encrypted_account_data bytea NOT NULL, account_last4 char(4) NOT NULL,
  is_default boolean NOT NULL DEFAULT false, is_active boolean NOT NULL DEFAULT true,
  verified_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_payout_dest_seller ON seller_payout_destinations(seller_profile_id,is_active);
CREATE UNIQUE INDEX uq_payout_dest_default ON seller_payout_destinations(seller_profile_id)
 WHERE is_default AND is_active;

CREATE TABLE categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id uuid REFERENCES categories(id) ON DELETE RESTRICT,
  category_kind varchar(10) NOT NULL CHECK(category_kind IN ('product','service','both')),
  slug text NOT NULL UNIQUE, display_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_categories_parent ON categories(parent_id,is_active,display_order);
CREATE TABLE category_translations (
  category_id uuid NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  language_code varchar(5) NOT NULL REFERENCES languages(code),
  name text NOT NULL, description text, PRIMARY KEY(category_id,language_code)
);

CREATE TABLE listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  category_id uuid NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES locations(id) ON DELETE SET NULL,
  listing_type varchar(8) NOT NULL CHECK(listing_type IN ('product','service')),
  sale_model varchar(12) NOT NULL CHECK(sale_model IN ('marketplace','consignment','jema_owned')),
  status varchar(18) NOT NULL DEFAULT 'draft'
    CHECK(status IN ('draft','pending_review','published','paused','rejected','archived','sold_out')),
  slug text NOT NULL, condition_code varchar(12) CHECK(condition_code IN ('new','used','refurbished')),
  base_price numeric(19,4) NOT NULL CHECK(base_price>=0), currency_code char(3) NOT NULL REFERENCES currencies(code),
  price_negotiable boolean NOT NULL DEFAULT false, service_duration_minutes integer,
  published_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(seller_profile_id,slug), UNIQUE(id,seller_profile_id),
  CHECK((listing_type='product' AND service_duration_minutes IS NULL) OR
        (listing_type='service' AND (condition_code IS NULL OR condition_code='new') AND
         (service_duration_minutes IS NULL OR service_duration_minutes>0)))
);
CREATE INDEX idx_listings_browse ON listings(status,category_id,created_at DESC,id DESC);
CREATE INDEX idx_listings_location ON listings(location_id,status,created_at DESC,id DESC);
CREATE INDEX idx_listings_seller ON listings(seller_profile_id,status,created_at DESC,id DESC);
CREATE INDEX idx_listings_price ON listings(status,currency_code,base_price);
CREATE INDEX idx_listings_type_model ON listings(listing_type,sale_model,status);

CREATE TABLE listing_translations (
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  language_code varchar(5) NOT NULL REFERENCES languages(code),
  title text NOT NULL, description text,
  search_vector tsvector GENERATED ALWAYS AS
    (to_tsvector('simple'::regconfig,coalesce(title,'')||' '||coalesce(description,''))) STORED,
  PRIMARY KEY(listing_id,language_code)
);
CREATE INDEX idx_listing_search ON listing_translations USING GIN(search_vector);
CREATE INDEX idx_listing_title ON listing_translations(language_code,lower(title));

CREATE TABLE listing_media (
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  file_asset_id uuid NOT NULL REFERENCES file_assets(id) ON DELETE RESTRICT,
  sort_order smallint NOT NULL DEFAULT 0 CHECK(sort_order>=0), alt_text text,
  PRIMARY KEY(listing_id,file_asset_id), UNIQUE(listing_id,sort_order)
);

CREATE TABLE listing_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  sku text, label text NOT NULL, attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  price_override numeric(19,4) CHECK(price_override IS NULL OR price_override>=0),
  currency_code char(3) REFERENCES currencies(code),
  is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(listing_id,id),
  CHECK((price_override IS NULL AND currency_code IS NULL) OR (price_override IS NOT NULL AND currency_code IS NOT NULL))
);
CREATE UNIQUE INDEX uq_variant_sku ON listing_variants(listing_id,sku) WHERE sku IS NOT NULL;
CREATE INDEX idx_variants_listing ON listing_variants(listing_id,is_active);

CREATE TABLE commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_model varchar(12) NOT NULL CHECK(sale_model IN ('marketplace','consignment','sourcing')),
  category_id uuid REFERENCES categories(id) ON DELETE RESTRICT,
  payer varchar(8) NOT NULL CHECK(payer IN ('seller','buyer','split')),
  calculation_basis varchar(16) NOT NULL DEFAULT 'items_subtotal'
    CHECK(calculation_basis IN ('items_subtotal','order_total')),
  percentage_rate numeric(9,6) NOT NULL DEFAULT 0 CHECK(percentage_rate BETWEEN 0 AND 100),
  fixed_fee_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(fixed_fee_amount>=0),
  fixed_fee_currency_code char(3) REFERENCES currencies(code),
  is_active boolean NOT NULL DEFAULT false, effective_from timestamptz NOT NULL, effective_until timestamptz,
  created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(fixed_fee_amount=0 OR fixed_fee_currency_code IS NOT NULL),
  CHECK(percentage_rate>0 OR fixed_fee_amount>0),
  CHECK(effective_until IS NULL OR effective_until>effective_from)
);
CREATE INDEX idx_commission_lookup ON commission_rules(sale_model,category_id,is_active,effective_from DESC);

CREATE TABLE fx_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  base_currency_code char(3) NOT NULL REFERENCES currencies(code),
  quote_currency_code char(3) NOT NULL REFERENCES currencies(code),
  rate numeric(24,12) NOT NULL CHECK(rate>0), rate_source varchar(30) NOT NULL DEFAULT 'jema_commercial',
  is_active boolean NOT NULL DEFAULT true, valid_from timestamptz NOT NULL, valid_until timestamptz,
  created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(base_currency_code<>quote_currency_code), CHECK(valid_until IS NULL OR valid_until>valid_from),
  UNIQUE NULLS NOT DISTINCT(base_currency_code,quote_currency_code,valid_from)
);
CREATE INDEX idx_fx_current ON fx_rates(base_currency_code,quote_currency_code,is_active,valid_from DESC);
INSERT INTO fx_rates(base_currency_code,quote_currency_code,rate,rate_source,valid_from) VALUES
 ('USD','CDF',2300.000000000000,'jema_commercial',TIMESTAMPTZ '2026-11-06 00:00:00+00'),
 ('CDF','USD',0.000434782609,'jema_commercial',TIMESTAMPTZ '2026-11-06 00:00:00+00');

CREATE TABLE consignment_mandates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consignor_seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  agent_seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  contract_reference text,
  status varchar(14) NOT NULL DEFAULT 'draft'
   CHECK(status IN ('draft','submitted','approved','active','rejected','expired','closed')),
  terms jsonb NOT NULL DEFAULT '{}'::jsonb, starts_at timestamptz, ends_at timestamptz,
  approved_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL, approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(consignor_seller_profile_id<>agent_seller_profile_id),
  CHECK(ends_at IS NULL OR starts_at IS NULL OR ends_at>starts_at)
);
CREATE INDEX idx_mandates_consignor ON consignment_mandates(consignor_seller_profile_id,status,created_at DESC);

CREATE TABLE consignment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mandate_id uuid NOT NULL REFERENCES consignment_mandates(id) ON DELETE RESTRICT,
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
  stock_owner_seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  price_floor numeric(19,4) NOT NULL CHECK(price_floor>=0),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  authorized_quantity integer NOT NULL CHECK(authorized_quantity>0),
  received_quantity integer NOT NULL DEFAULT 0 CHECK(received_quantity>=0),
  status varchar(12) NOT NULL DEFAULT 'proposed'
   CHECK(status IN ('proposed','approved','active','paused','completed','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(mandate_id,listing_id)
);
CREATE INDEX idx_consignment_owner ON consignment_items(stock_owner_seller_profile_id,status);

CREATE TABLE inventory_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
  variant_id uuid, stock_owner_seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  on_hand_quantity integer NOT NULL DEFAULT 0 CHECK(on_hand_quantity>=0),
  reserved_quantity integer NOT NULL DEFAULT 0 CHECK(reserved_quantity>=0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(listing_id,variant_id) REFERENCES listing_variants(listing_id,id) ON DELETE RESTRICT,
  CHECK(reserved_quantity<=on_hand_quantity),
  UNIQUE NULLS NOT DISTINCT(listing_id,variant_id,stock_owner_seller_profile_id)
);
CREATE INDEX idx_inventory_listing ON inventory_balances(listing_id,variant_id);

CREATE TABLE stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_balance_id uuid NOT NULL REFERENCES inventory_balances(id) ON DELETE RESTRICT,
  movement_type varchar(12) NOT NULL CHECK(movement_type IN ('received','sold','reserved','released','adjustment','returned','damaged')),
  quantity_delta integer NOT NULL CHECK(quantity_delta<>0),
  reference_type varchar(24), reference_id uuid, note text,
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_stock_movements_timeline ON stock_movements(inventory_balance_id,created_at DESC);

CREATE TABLE consignment_mandate_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mandate_id uuid NOT NULL REFERENCES consignment_mandates(id) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  action_code varchar(32) NOT NULL, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sourcing_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_number text NOT NULL UNIQUE,
  buyer_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES locations(id) ON DELETE SET NULL,
  preferred_currency_code char(3) NOT NULL REFERENCES currencies(code),
  budget_min numeric(19,4) CHECK(budget_min IS NULL OR budget_min>=0),
  budget_max numeric(19,4) CHECK(budget_max IS NULL OR budget_max>=0),
  needed_by date, status varchar(18) NOT NULL DEFAULT 'submitted'
   CHECK(status IN ('submitted','researching','quoted','negotiating','accepted','rejected','expired','unavailable','fulfilled','cancelled')),
  customer_note text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(budget_min IS NULL OR budget_max IS NULL OR budget_max>=budget_min)
);
CREATE INDEX idx_sourcing_buyer_page ON sourcing_requests(buyer_user_id,created_at DESC,id DESC);
CREATE INDEX idx_sourcing_queue ON sourcing_requests(status,created_at,id);

CREATE TABLE sourcing_request_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sourcing_request_id uuid NOT NULL REFERENCES sourcing_requests(id) ON DELETE CASCADE,
  requested_name text NOT NULL, description text, specifications jsonb NOT NULL DEFAULT '{}'::jsonb,
  quantity integer NOT NULL CHECK(quantity>0), created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sourcing_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sourcing_request_id uuid NOT NULL REFERENCES sourcing_requests(id) ON DELETE RESTRICT,
  version integer NOT NULL CHECK(version>0), prepared_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  product_cost_amount numeric(19,4) NOT NULL CHECK(product_cost_amount>=0),
  commission_amount numeric(19,4) NOT NULL CHECK(commission_amount>=0),
  additional_fees_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(additional_fees_amount>=0),
  total_amount numeric(19,4) NOT NULL CHECK(total_amount>=0),
  fx_rate_snapshot numeric(24,12) CHECK(fx_rate_snapshot IS NULL OR fx_rate_snapshot>0),
  status varchar(12) NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','sent','negotiating','accepted','rejected','expired','converted')),
  valid_until timestamptz, accepted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(sourcing_request_id,version),
  CHECK(total_amount=product_cost_amount+commission_amount+additional_fees_amount)
);
CREATE INDEX idx_sourcing_quotes_request ON sourcing_quotes(sourcing_request_id,version DESC);

CREATE TABLE sourcing_quote_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sourcing_quote_id uuid NOT NULL REFERENCES sourcing_quotes(id) ON DELETE CASCADE,
  sourcing_request_item_id uuid REFERENCES sourcing_request_items(id) ON DELETE SET NULL,
  item_name_snapshot text NOT NULL, quantity integer NOT NULL CHECK(quantity>0),
  unit_product_cost numeric(19,4) NOT NULL CHECK(unit_product_cost>=0),
  commission_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(commission_amount>=0),
  fees_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(fees_amount>=0),
  line_total_amount numeric(19,4) NOT NULL CHECK(line_total_amount>=0),
  CHECK(line_total_amount=unit_product_cost*quantity+commission_amount+fees_amount)
);

CREATE TABLE carts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status varchar(10) NOT NULL DEFAULT 'active' CHECK(status IN ('active','converted','abandoned')),
  currency_code char(3) REFERENCES currencies(code),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_active_cart ON carts(buyer_user_id) WHERE status='active';
CREATE TABLE cart_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id uuid NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
  variant_id uuid, quantity integer NOT NULL CHECK(quantity>0), added_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(listing_id,variant_id) REFERENCES listing_variants(listing_id,id) ON DELETE RESTRICT,
  UNIQUE NULLS NOT DISTINCT(cart_id,listing_id,variant_id)
);
CREATE INDEX idx_cart_items_cart ON cart_items(cart_id);

CREATE TABLE orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_number text NOT NULL UNIQUE,
  buyer_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  source_quote_id uuid REFERENCES sourcing_quotes(id) ON DELETE RESTRICT,
  status varchar(18) NOT NULL DEFAULT 'pending_payment'
   CHECK(status IN ('draft','pending_payment','paid','processing','partially_shipped','shipped','completed','cancelled','disputed','refunded')),
  payment_status varchar(18) NOT NULL DEFAULT 'unpaid'
   CHECK(payment_status IN ('unpaid','pending','partially_paid','paid','partially_refunded','refunded','failed')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  subtotal_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(subtotal_amount>=0),
  shipping_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(shipping_amount>=0),
  discount_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(discount_amount>=0),
  tax_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(tax_amount>=0),
  total_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(total_amount>=0),
  delivery_address_snapshot jsonb, buyer_note text, placed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(total_amount=subtotal_amount+shipping_amount-discount_amount+tax_amount)
);
CREATE INDEX idx_orders_buyer_page ON orders(buyer_user_id,placed_at DESC,id DESC);
CREATE INDEX idx_orders_status_page ON orders(status,placed_at DESC,id DESC);
CREATE UNIQUE INDEX uq_order_quote ON orders(source_quote_id) WHERE source_quote_id IS NOT NULL;

CREATE TABLE seller_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  sale_model varchar(12) NOT NULL CHECK(sale_model IN ('marketplace','consignment','jema_owned','sourcing')),
  suborder_number text NOT NULL UNIQUE,
  status varchar(16) NOT NULL DEFAULT 'pending_payment'
   CHECK(status IN ('pending_payment','paid','processing','ready','shipped','completed','cancelled','disputed','refunded')),
  payment_status varchar(16) NOT NULL DEFAULT 'unpaid'
   CHECK(payment_status IN ('unpaid','pending','paid','partially_refunded','refunded','failed')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  subtotal_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(subtotal_amount>=0),
  shipping_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(shipping_amount>=0),
  discount_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(discount_amount>=0),
  total_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(total_amount>=0),
  delivery_address_snapshot jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id,seller_profile_id,sale_model),
  CHECK(total_amount=subtotal_amount+shipping_amount-discount_amount)
);
CREATE INDEX idx_seller_orders_seller_page ON seller_orders(seller_profile_id,created_at DESC,id DESC);
CREATE INDEX idx_seller_orders_status_page ON seller_orders(status,created_at DESC,id DESC);
CREATE INDEX idx_seller_orders_parent ON seller_orders(order_id);

CREATE TABLE order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_order_id uuid NOT NULL REFERENCES seller_orders(id) ON DELETE RESTRICT,
  listing_id uuid REFERENCES listings(id) ON DELETE RESTRICT,
  variant_id uuid, sourcing_quote_item_id uuid REFERENCES sourcing_quote_items(id) ON DELETE RESTRICT,
  title_snapshot text NOT NULL, variant_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  sale_model_snapshot varchar(12) NOT NULL CHECK(sale_model_snapshot IN ('marketplace','consignment','jema_owned','sourcing')),
  quantity integer NOT NULL CHECK(quantity>0),
  original_unit_price numeric(19,4) NOT NULL CHECK(original_unit_price>=0),
  original_currency_code char(3) NOT NULL REFERENCES currencies(code),
  exchange_rate_snapshot numeric(24,12) NOT NULL DEFAULT 1 CHECK(exchange_rate_snapshot>0),
  unit_price_amount numeric(19,4) NOT NULL CHECK(unit_price_amount>=0),
  line_discount_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(line_discount_amount>=0),
  line_total_amount numeric(19,4) NOT NULL CHECK(line_total_amount>=0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(listing_id,variant_id) REFERENCES listing_variants(listing_id,id) ON DELETE RESTRICT,
  CHECK((listing_id IS NOT NULL AND sourcing_quote_item_id IS NULL) OR
        (listing_id IS NULL AND variant_id IS NULL AND sourcing_quote_item_id IS NOT NULL)),
  CHECK(line_total_amount=unit_price_amount*quantity-line_discount_amount)
);
CREATE UNIQUE INDEX uq_order_item_variant ON order_items(seller_order_id,listing_id,variant_id) NULLS NOT DISTINCT;
CREATE INDEX idx_order_items_suborder ON order_items(seller_order_id);
CREATE INDEX idx_order_items_listing ON order_items(listing_id) WHERE listing_id IS NOT NULL;

CREATE TABLE order_status_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES orders(id) ON DELETE RESTRICT,
  seller_order_id uuid REFERENCES seller_orders(id) ON DELETE RESTRICT,
  previous_status varchar(18), new_status varchar(18) NOT NULL,
  changed_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  reason text, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(num_nonnulls(order_id,seller_order_id)=1)
);
CREATE INDEX idx_order_events_parent ON order_status_events(order_id,created_at DESC) WHERE order_id IS NOT NULL;
CREATE INDEX idx_order_events_seller ON order_status_events(seller_order_id,created_at DESC) WHERE seller_order_id IS NOT NULL;

CREATE TABLE stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_balance_id uuid NOT NULL REFERENCES inventory_balances(id) ON DELETE RESTRICT,
  order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK(quantity>0),
  status varchar(10) NOT NULL DEFAULT 'active' CHECK(status IN ('active','committed','released','expired')),
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL, resolved_at timestamptz,
  CHECK(expires_at>created_at), UNIQUE(inventory_balance_id,order_item_id)
);
CREATE INDEX idx_stock_reservation_expiry ON stock_reservations(expires_at) WHERE status='active';

CREATE TABLE service_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id uuid NOT NULL UNIQUE REFERENCES order_items(id) ON DELETE RESTRICT,
  provider_seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  requested_start_at timestamptz NOT NULL, requested_end_at timestamptz NOT NULL,
  confirmed_start_at timestamptz, confirmed_end_at timestamptz,
  status varchar(12) NOT NULL DEFAULT 'requested'
   CHECK(status IN ('requested','confirmed','rejected','in_progress','completed','cancelled')),
  customer_note text, provider_note text, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(requested_end_at>requested_start_at),
  CHECK(confirmed_end_at IS NULL OR confirmed_start_at IS NULL OR confirmed_end_at>confirmed_start_at)
);
CREATE INDEX idx_service_booking_schedule ON service_bookings(provider_seller_profile_id,requested_start_at,status);

CREATE TABLE shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_order_id uuid NOT NULL REFERENCES seller_orders(id) ON DELETE RESTRICT,
  delivery_method varchar(16) NOT NULL CHECK(delivery_method IN ('courier','seller_delivery','pickup','digital','other')),
  carrier_name text, tracking_number text,
  status varchar(12) NOT NULL DEFAULT 'pending'
   CHECK(status IN ('pending','ready','in_transit','delivered','failed','returned','cancelled')),
  shipping_fee_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(shipping_fee_amount>=0),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  shipped_at timestamptz, delivered_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_shipments_seller_order ON shipments(seller_order_id,created_at);
CREATE INDEX idx_shipments_tracking ON shipments(carrier_name,tracking_number) WHERE tracking_number IS NOT NULL;

CREATE TABLE shipment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
  event_code varchar(30) NOT NULL, description text, event_location text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX idx_shipment_events_page ON shipment_events(shipment_id,occurred_at DESC);

CREATE TABLE commission_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_order_id uuid NOT NULL UNIQUE REFERENCES seller_orders(id) ON DELETE RESTRICT,
  commission_rule_id uuid REFERENCES commission_rules(id) ON DELETE SET NULL,
  calculation_basis_amount numeric(19,4) NOT NULL CHECK(calculation_basis_amount>=0),
  percentage_rate numeric(9,6) NOT NULL DEFAULT 0 CHECK(percentage_rate BETWEEN 0 AND 100),
  fixed_fee_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(fixed_fee_amount>=0),
  commission_amount numeric(19,4) NOT NULL CHECK(commission_amount>=0),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  payer varchar(8) NOT NULL CHECK(payer IN ('seller','buyer','split')),
  status varchar(10) NOT NULL DEFAULT 'due' CHECK(status IN ('due','paid','waived','reversed')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_commission_status ON commission_snapshots(status,created_at DESC);

CREATE TABLE payment_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  seller_order_id uuid REFERENCES seller_orders(id) ON DELETE RESTRICT,
  initiated_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  provider_code varchar(16) NOT NULL CHECK(provider_code IN ('mpesa','airtel_money','orange_money')),
  payment_method varchar(20) NOT NULL DEFAULT 'mobile_money',
  status varchar(18) NOT NULL DEFAULT 'created'
   CHECK(status IN ('created','pending','succeeded','failed','cancelled','expired','partially_refunded','refunded')),
  amount numeric(19,4) NOT NULL CHECK(amount>0), currency_code char(3) NOT NULL REFERENCES currencies(code),
  idempotency_key text NOT NULL, provider_reference text, payer_phone_last4 char(4),
  initiated_at timestamptz NOT NULL DEFAULT now(), confirmed_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider_code,idempotency_key)
);
CREATE UNIQUE INDEX uq_payment_provider_ref ON payment_attempts(provider_code,provider_reference) WHERE provider_reference IS NOT NULL;
CREATE INDEX idx_payment_order ON payment_attempts(order_id,initiated_at DESC);
CREATE INDEX idx_payment_suborder ON payment_attempts(seller_order_id,initiated_at DESC) WHERE seller_order_id IS NOT NULL;
CREATE INDEX idx_payment_status ON payment_attempts(status,initiated_at DESC);

CREATE TABLE payment_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_attempt_id uuid NOT NULL REFERENCES payment_attempts(id) ON DELETE RESTRICT,
  seller_order_id uuid NOT NULL REFERENCES seller_orders(id) ON DELETE RESTRICT,
  allocated_amount numeric(19,4) NOT NULL CHECK(allocated_amount>0),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(payment_attempt_id,seller_order_id)
);
CREATE INDEX idx_payment_allocations_seller ON payment_allocations(seller_order_id);

CREATE TABLE payment_provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_code varchar(16) NOT NULL CHECK(provider_code IN ('mpesa','airtel_money','orange_money')),
  provider_event_id text NOT NULL, payment_attempt_id uuid REFERENCES payment_attempts(id) ON DELETE RESTRICT,
  event_type varchar(50) NOT NULL, signature_valid boolean NOT NULL,
  redacted_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz, processing_error text,
  UNIQUE(provider_code,provider_event_id)
);
CREATE INDEX idx_provider_events_pending ON payment_provider_events(received_at) WHERE processed_at IS NULL;

CREATE TABLE refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_attempt_id uuid NOT NULL REFERENCES payment_attempts(id) ON DELETE RESTRICT,
  seller_order_id uuid REFERENCES seller_orders(id) ON DELETE RESTRICT,
  requested_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  approved_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  amount numeric(19,4) NOT NULL CHECK(amount>0), currency_code char(3) NOT NULL REFERENCES currencies(code),
  reason text NOT NULL, status varchar(12) NOT NULL DEFAULT 'requested'
   CHECK(status IN ('requested','approved','submitted','succeeded','failed','rejected','cancelled')),
  provider_reference text, idempotency_key text NOT NULL UNIQUE,
  requested_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX idx_refunds_payment ON refunds(payment_attempt_id,requested_at DESC);
CREATE INDEX idx_refunds_status ON refunds(status,requested_at);

CREATE TABLE financial_ledger_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_code varchar(50) NOT NULL,
  account_name text NOT NULL,
  account_type varchar(10) NOT NULL CHECK(account_type IN ('asset','liability','income','expense','equity')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  seller_profile_id uuid REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(account_code,currency_code), UNIQUE(id,currency_code)
);
INSERT INTO financial_ledger_accounts(account_code,account_name,account_type,currency_code)
SELECT x.code,x.name,x.kind,c.code
FROM (VALUES
 ('PSP_CLEARING','Fonds en transit','asset'),('SELLER_PAYABLE','Sommes dues aux vendeurs','liability'),
 ('JEMA_COMMISSION_REVENUE','Commissions Jema','income'),('JEMA_SALES_REVENUE','Ventes propres Jema','income'),
 ('REFUNDS_PAYABLE','Remboursements à effectuer','liability'),('PROCESSOR_FEES','Frais opérateurs','expense')
) AS x(code,name,kind) CROSS JOIN currencies c;

CREATE TABLE financial_ledger_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), transaction_reference text NOT NULL UNIQUE,
  source_type varchar(30) NOT NULL, source_id uuid, idempotency_key text NOT NULL UNIQUE,
  status varchar(10) NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','posted','reversed')),
  description text, created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), posted_at timestamptz, reversed_at timestamptz,
  CHECK(status<>'posted' OR posted_at IS NOT NULL)
);

CREATE TABLE financial_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES financial_ledger_transactions(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL, currency_code char(3) NOT NULL REFERENCES currencies(code),
  debit_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(debit_amount>=0),
  credit_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(credit_amount>=0),
  memo text, created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(account_id,currency_code) REFERENCES financial_ledger_accounts(id,currency_code) ON DELETE RESTRICT,
  CHECK((debit_amount>0 AND credit_amount=0) OR (credit_amount>0 AND debit_amount=0))
);
CREATE INDEX idx_ledger_tx_entries ON financial_ledger_entries(transaction_id);
CREATE INDEX idx_ledger_account_page ON financial_ledger_entries(account_id,created_at DESC);

CREATE OR REPLACE FUNCTION jema_check_ledger_balance()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_id uuid; target_status varchar(10);
BEGIN
  IF TG_TABLE_NAME='financial_ledger_entries' THEN
    target_id:=COALESCE(NEW.transaction_id,OLD.transaction_id);
  ELSE
    target_id:=COALESCE(NEW.id,OLD.id);
  END IF;
  SELECT status INTO target_status FROM financial_ledger_transactions WHERE id=target_id;
  IF target_status='posted' THEN
    IF NOT EXISTS(SELECT 1 FROM financial_ledger_entries WHERE transaction_id=target_id) OR
       EXISTS(SELECT currency_code FROM financial_ledger_entries WHERE transaction_id=target_id
              GROUP BY currency_code HAVING SUM(debit_amount)<>SUM(credit_amount)) THEN
      RAISE EXCEPTION 'Une écriture publiée doit être équilibrée par devise.';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER trg_ledger_entries_balanced
AFTER INSERT OR UPDATE OR DELETE ON financial_ledger_entries
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION jema_check_ledger_balance();
CREATE CONSTRAINT TRIGGER trg_ledger_header_balanced
AFTER INSERT OR UPDATE ON financial_ledger_transactions
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION jema_check_ledger_balance();

CREATE TABLE seller_payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payout_number text NOT NULL UNIQUE,
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  destination_id uuid NOT NULL REFERENCES seller_payout_destinations(id) ON DELETE RESTRICT,
  provider_code varchar(16) NOT NULL CHECK(provider_code IN ('mpesa','airtel_money','orange_money')),
  status varchar(16) NOT NULL DEFAULT 'draft'
   CHECK(status IN ('draft','pending_approval','approved','submitted','paid','failed','cancelled','blocked')),
  amount numeric(19,4) NOT NULL CHECK(amount>0), currency_code char(3) NOT NULL REFERENCES currencies(code),
  provider_reference text, idempotency_key text NOT NULL UNIQUE,
  requested_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  approved_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), submitted_at timestamptz, paid_at timestamptz
);
CREATE INDEX idx_payout_seller_page ON seller_payouts(seller_profile_id,created_at DESC);
CREATE INDEX idx_payout_status ON seller_payouts(status,created_at);

CREATE TABLE seller_payout_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_payout_id uuid NOT NULL REFERENCES seller_payouts(id) ON DELETE RESTRICT,
  seller_order_id uuid NOT NULL REFERENCES seller_orders(id) ON DELETE RESTRICT,
  gross_amount numeric(19,4) NOT NULL CHECK(gross_amount>=0),
  commission_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(commission_amount>=0),
  fees_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(fees_amount>=0),
  net_amount numeric(19,4) NOT NULL CHECK(net_amount>=0),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  UNIQUE(seller_payout_id,seller_order_id),
  CHECK(net_amount=gross_amount-commission_amount-fees_amount)
);
CREATE INDEX idx_payout_lines_order ON seller_payout_lines(seller_order_id);

CREATE TABLE negotiation_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  listing_id uuid REFERENCES listings(id) ON DELETE RESTRICT,
  sourcing_request_id uuid REFERENCES sourcing_requests(id) ON DELETE RESTRICT,
  status varchar(12) NOT NULL DEFAULT 'open' CHECK(status IN ('open','accepted','rejected','expired','closed')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(num_nonnulls(listing_id,sourcing_request_id)=1)
);
CREATE INDEX idx_negotiation_buyer ON negotiation_threads(buyer_user_id,updated_at DESC);
CREATE INDEX idx_negotiation_seller ON negotiation_threads(seller_profile_id,updated_at DESC);

CREATE TABLE negotiation_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES negotiation_threads(id) ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK(revision_number>0),
  proposed_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  unit_price_amount numeric(19,4) NOT NULL CHECK(unit_price_amount>=0),
  quantity integer NOT NULL CHECK(quantity>0), shipping_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(shipping_amount>=0),
  other_fees_amount numeric(19,4) NOT NULL DEFAULT 0 CHECK(other_fees_amount>=0),
  total_amount numeric(19,4) NOT NULL CHECK(total_amount>=0),
  currency_code char(3) NOT NULL REFERENCES currencies(code), message text,
  status varchar(12) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','rejected','countered','expired','cancelled')),
  expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), responded_at timestamptz,
  UNIQUE(thread_id,revision_number),
  CHECK(total_amount=unit_price_amount*quantity+shipping_amount+other_fees_amount)
);
CREATE INDEX idx_negotiation_offer_page ON negotiation_offers(thread_id,revision_number DESC);

CREATE TABLE support_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opened_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  assigned_to_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  order_id uuid REFERENCES orders(id) ON DELETE RESTRICT,
  seller_order_id uuid REFERENCES seller_orders(id) ON DELETE RESTRICT,
  sourcing_request_id uuid REFERENCES sourcing_requests(id) ON DELETE RESTRICT,
  subject text NOT NULL, description text NOT NULL,
  priority varchar(8) NOT NULL DEFAULT 'normal' CHECK(priority IN ('low','normal','high','urgent')),
  status varchar(14) NOT NULL DEFAULT 'open' CHECK(status IN ('open','in_progress','waiting_user','resolved','closed')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz, CHECK(num_nonnulls(order_id,seller_order_id,sourcing_request_id)<=1)
);
CREATE INDEX idx_support_queue ON support_cases(status,priority,created_at);
CREATE INDEX idx_support_user ON support_cases(opened_by_user_id,created_at DESC);

CREATE TABLE disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_order_id uuid NOT NULL UNIQUE REFERENCES seller_orders(id) ON DELETE RESTRICT,
  opened_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  assigned_to_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  reason_code varchar(30) NOT NULL, description text NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'open'
   CHECK(status IN ('open','investigating','awaiting_evidence','resolved_buyer','resolved_seller','closed')),
  resolution_note text, created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX idx_disputes_queue ON disputes(status,created_at);

CREATE TABLE return_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_order_id uuid NOT NULL REFERENCES seller_orders(id) ON DELETE RESTRICT,
  requested_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reason_code varchar(30) NOT NULL, description text,
  status varchar(14) NOT NULL DEFAULT 'requested'
   CHECK(status IN ('requested','approved','rejected','in_transit','received','refunded','closed')),
  requested_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX idx_returns_suborder ON return_requests(seller_order_id,requested_at DESC);
CREATE TABLE return_request_items (
  return_request_id uuid NOT NULL REFERENCES return_requests(id) ON DELETE CASCADE,
  order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK(quantity>0), PRIMARY KEY(return_request_id,order_item_id)
);

CREATE TABLE conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_type varchar(10) NOT NULL CHECK(conversation_type IN ('direct','order','sourcing','support','group')),
  seller_order_id uuid REFERENCES seller_orders(id) ON DELETE RESTRICT,
  sourcing_request_id uuid REFERENCES sourcing_requests(id) ON DELETE RESTRICT,
  support_case_id uuid REFERENCES support_cases(id) ON DELETE RESTRICT,
  created_by_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status varchar(10) NOT NULL DEFAULT 'active' CHECK(status IN ('active','closed','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(num_nonnulls(seller_order_id,sourcing_request_id,support_case_id)<=1),
  CHECK((conversation_type='order' AND seller_order_id IS NOT NULL) OR
        (conversation_type='sourcing' AND sourcing_request_id IS NOT NULL) OR
        (conversation_type='support' AND support_case_id IS NOT NULL) OR
        (conversation_type IN ('direct','group') AND seller_order_id IS NULL AND
         sourcing_request_id IS NULL AND support_case_id IS NULL))
);
CREATE UNIQUE INDEX uq_order_conversation ON conversations(seller_order_id) WHERE conversation_type='order';
CREATE UNIQUE INDEX uq_sourcing_conversation ON conversations(sourcing_request_id) WHERE conversation_type='sourcing';
CREATE UNIQUE INDEX uq_support_conversation ON conversations(support_case_id) WHERE conversation_type='support';

CREATE TABLE conversation_participants (
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  participant_role varchar(8) NOT NULL DEFAULT 'member' CHECK(participant_role IN ('buyer','seller','agent','member')),
  joined_at timestamptz NOT NULL DEFAULT now(), left_at timestamptz, last_read_at timestamptz,
  is_muted boolean NOT NULL DEFAULT false, PRIMARY KEY(conversation_id,user_id)
);
CREATE INDEX idx_conversation_participant_user ON conversation_participants(user_id,joined_at DESC);

CREATE TABLE exchange_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL UNIQUE REFERENCES conversations(id) ON DELETE CASCADE,
  owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  name text NOT NULL, slug text NOT NULL UNIQUE, description text,
  visibility varchar(8) NOT NULL CHECK(visibility IN ('public','private')),
  status varchar(8) NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','closed')),
  rules text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE group_memberships (
  group_id uuid NOT NULL REFERENCES exchange_groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  role varchar(10) NOT NULL DEFAULT 'member' CHECK(role IN ('owner','admin','moderator','member')),
  status varchar(10) NOT NULL DEFAULT 'active' CHECK(status IN ('pending','active','left','banned')),
  joined_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(group_id,user_id)
);
CREATE INDEX idx_group_members_user ON group_memberships(user_id,status);

CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reply_to_message_id uuid REFERENCES messages(id) ON DELETE SET NULL,
  message_type varchar(8) NOT NULL DEFAULT 'text' CHECK(message_type IN ('text','file','system')),
  body text, sent_at timestamptz NOT NULL DEFAULT now(), edited_at timestamptz, deleted_at timestamptz,
  CHECK((message_type='text' AND body IS NOT NULL) OR message_type IN ('file','system'))
);
CREATE INDEX idx_messages_page ON messages(conversation_id,sent_at DESC,id DESC);
CREATE INDEX idx_messages_sender ON messages(sender_user_id,sent_at DESC);

CREATE TABLE message_attachments (
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  file_asset_id uuid NOT NULL REFERENCES file_assets(id) ON DELETE RESTRICT,
  PRIMARY KEY(message_id,file_asset_id)
);

CREATE TABLE user_blocks (
  blocker_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason text, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(blocker_user_id,blocked_user_id), CHECK(blocker_user_id<>blocked_user_id)
);

CREATE TABLE user_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  target_type varchar(12) NOT NULL CHECK(target_type IN ('user','listing','message','group','conversation')),
  target_id uuid NOT NULL, reason_code varchar(30) NOT NULL, details text,
  status varchar(10) NOT NULL DEFAULT 'open' CHECK(status IN ('open','reviewing','actioned','dismissed')),
  assigned_to_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX idx_reports_queue ON user_reports(status,created_at);

CREATE TABLE moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moderator_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  report_id uuid REFERENCES user_reports(id) ON DELETE RESTRICT,
  target_type varchar(16) NOT NULL, target_id uuid NOT NULL, action_code varchar(30) NOT NULL,
  reason text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_moderation_target ON moderation_actions(target_type,target_id,created_at DESC);

CREATE TABLE notification_preferences (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel varchar(8) NOT NULL CHECK(channel IN ('in_app','email','sms','push')),
  notification_type varchar(40) NOT NULL, is_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,channel,notification_type)
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notification_type varchar(40) NOT NULL,
  channel varchar(8) NOT NULL DEFAULT 'in_app' CHECK(channel IN ('in_app','email','sms','push')),
  language_code varchar(5) NOT NULL DEFAULT 'fr' REFERENCES languages(code),
  title text NOT NULL, body text NOT NULL, payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status varchar(8) NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','sent','failed','read')),
  created_at timestamptz NOT NULL DEFAULT now(), sent_at timestamptz, read_at timestamptz
);
CREATE INDEX idx_notifications_user_page ON notifications(user_id,created_at DESC,id DESC);
CREATE INDEX idx_notifications_queue ON notifications(status,created_at) WHERE status='queued';

CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,
  author_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  seller_profile_id uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE RESTRICT,
  rating smallint NOT NULL CHECK(rating BETWEEN 1 AND 5), review_text text,
  status varchar(10) NOT NULL DEFAULT 'published' CHECK(status IN ('pending','published','hidden')),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(order_item_id,author_user_id)
);
CREATE INDEX idx_reviews_seller_page ON reviews(seller_profile_id,status,created_at DESC,id DESC);

CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  action_code varchar(80) NOT NULL, entity_type varchar(40) NOT NULL, entity_id uuid,
  ip_address inet, user_agent text, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type,entity_id,created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_user_id,created_at DESC);
CREATE INDEX idx_audit_time ON audit_logs(created_at DESC);

CREATE TABLE idempotency_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  operation_scope varchar(100) NOT NULL, idempotency_key text NOT NULL,
  request_fingerprint char(64) NOT NULL, response_status integer, response_body jsonb,
  status varchar(12) NOT NULL DEFAULT 'processing' CHECK(status IN ('processing','complete','failed')),
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  UNIQUE NULLS NOT DISTINCT(actor_user_id,operation_scope,idempotency_key),
  CHECK(expires_at>created_at)
);
CREATE INDEX idx_idempotency_expiry ON idempotency_records(expires_at);

CREATE OR REPLACE FUNCTION jema_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at:=now(); RETURN NEW;
END;
$$;
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_addresses_updated_at BEFORE UPDATE ON user_addresses FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_sellers_updated_at BEFORE UPDATE ON seller_profiles FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_listings_updated_at BEFORE UPDATE ON listings FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_sourcing_updated_at BEFORE UPDATE ON sourcing_requests FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_carts_updated_at BEFORE UPDATE ON carts FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_seller_orders_updated_at BEFORE UPDATE ON seller_orders FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_service_bookings_updated_at BEFORE UPDATE ON service_bookings FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_negotiation_updated_at BEFORE UPDATE ON negotiation_threads FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();
CREATE TRIGGER trg_support_updated_at BEFORE UPDATE ON support_cases FOR EACH ROW EXECUTE FUNCTION jema_set_updated_at();

COMMIT;
