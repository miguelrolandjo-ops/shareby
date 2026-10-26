-- Shareby server schema for PostgreSQL 15+ / Supabase. Safe to re-run: every statement is idempotent.
--
-- Everything lives in its own schema, "shareby", NOT in "public". On Supabase the "public"
-- schema is published to the internet through the auto-generated REST API (PostgREST) with
-- the public anon key, so tables there would be readable by anyone. The app only ever talks
-- to the Shareby API; the database is never exposed directly.
--
-- Sync model:
--   * IDs are UUIDs generated on the device, so records can be created offline.
--   * updated_at is the client's edit time and drives last-write-wins.
--   * server_updated_at is set by the server on every write and drives /sync/pull cursors.
--   * Deletes are soft (deleted_at) so other devices learn about them. Tombstones older than
--     TOMBSTONE_DAYS (see src/maintenance.js) are purged; a device that was away longer gets
--     a full resync instead.
--
-- Kept lean for the Supabase free tier (500 MB): no audit trail, no session table (sign-in
-- tokens are signed, not stored), accepted invitations are deleted, and pictures are never
-- stored here, only the short address each device downloads them from.

CREATE SCHEMA IF NOT EXISTS shareby;
SET search_path TO shareby, public;

CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY,
  email         text NOT NULL UNIQUE,          -- stored lowercase
  display_name  text NOT NULL,
  provider      text NOT NULL                  -- google | apple | dev
);

CREATE TABLE IF NOT EXISTS folders (
  id                 uuid PRIMARY KEY,
  owner_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name               text NOT NULL,
  color              bigint NOT NULL,          -- ARGB int from the app (exceeds int4)
  emoji              text NOT NULL DEFAULT '📁',
  is_shared          boolean NOT NULL DEFAULT false,  -- fixed at creation
  created_at         timestamptz NOT NULL,
  updated_at         timestamptz NOT NULL,
  deleted_at         timestamptz,
  server_updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Every folder has its owner as a member, so access checks are one join.
CREATE TABLE IF NOT EXISTS folder_members (
  folder_id  uuid NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
  added_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (folder_id, user_id)
);

-- Invites for people who have not signed in yet. Deleted once accepted (on first sign-in);
-- unaccepted ones expire (see src/maintenance.js).
CREATE TABLE IF NOT EXISTS invitations (
  folder_id   uuid NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  email       text NOT NULL,                   -- stored lowercase
  role        text NOT NULL CHECK (role IN ('editor', 'viewer')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (folder_id, email)
);

CREATE TABLE IF NOT EXISTS items (
  id                     uuid PRIMARY KEY,
  owner_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- who saved / pinned it
  folder_id              uuid REFERENCES folders(id) ON DELETE SET NULL,        -- NULL = Uncategorized
  url                    text NOT NULL,
  title                  text NOT NULL,
  source                 text NOT NULL,        -- platform key from rules.json (instagram, shopee...) or web
  author                 text,                 -- who made the post, from the page title
  thumbnail_url          text,                 -- picture ADDRESS only; the picture itself stays on devices
  tag                    text,                 -- personal folders only (see trigger)
  status                 text NOT NULL CHECK (status IN ('new', 'confirmed')),
  suggested_folder_id    uuid,
  confidence             real NOT NULL DEFAULT 0,
  -- "Pinned" (named completed_* for compatibility with older apps). On shared boards a pin is
  -- shared by everyone; it has its own timestamp so it merges independently of content edits.
  completed_at           timestamptz,
  completed_by           uuid REFERENCES users(id) ON DELETE SET NULL,
  completion_updated_at  timestamptz,
  created_at             timestamptz NOT NULL,
  updated_at             timestamptz NOT NULL,
  deleted_at             timestamptz,
  server_updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Indexes shaped for /sync/pull: "what changed in my folders / my uncategorized since X".
CREATE INDEX IF NOT EXISTS items_folder_sync_idx  ON items (folder_id, server_updated_at);
CREATE INDEX IF NOT EXISTS items_loose_sync_idx   ON items (owner_id, server_updated_at) WHERE folder_id IS NULL;
CREATE INDEX IF NOT EXISTS items_owner_idx        ON items (owner_id);
CREATE INDEX IF NOT EXISTS items_deleted_idx      ON items (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS folders_owner_idx      ON folders (owner_id);
CREATE INDEX IF NOT EXISTS folders_deleted_idx    ON folders (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS members_user_idx       ON folder_members (user_id);
CREATE INDEX IF NOT EXISTS invitations_email_idx  ON invitations (email);

-- Product rule: tags and auto-categorization exist only for personal folders.
-- Enforced here as well as in the app, so no client can put a tag on a shared board.
CREATE OR REPLACE FUNCTION shareby.enforce_personal_tagging() RETURNS trigger
LANGUAGE plpgsql SET search_path = shareby, pg_temp AS $$
BEGIN
  IF NEW.folder_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM folders f WHERE f.id = NEW.folder_id AND f.is_shared) THEN
    NEW.tag := NULL;
    NEW.status := 'confirmed';
    NEW.suggested_folder_id := NULL;
    NEW.confidence := 0;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS items_personal_tagging ON items;
CREATE TRIGGER items_personal_tagging
  BEFORE INSERT OR UPDATE OF folder_id, tag, status, suggested_folder_id, confidence ON items
  FOR EACH ROW EXECUTE FUNCTION shareby.enforce_personal_tagging();

-- Defence in depth for Supabase: even if someone adds "shareby" to the exposed API schemas,
-- the public API roles get nothing. Row Level Security with no policies denies everything to
-- them; the API connects as the table owner, which RLS does not restrict.
ALTER TABLE users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE folder_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations    ENABLE ROW LEVEL SECURITY;
ALTER TABLE items          ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('REVOKE ALL ON SCHEMA shareby FROM %I', r);
      EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA shareby FROM %I', r);
      EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA shareby FROM %I', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA shareby REVOKE ALL ON TABLES FROM %I', r);
    END IF;
  END LOOP;
END $$;
