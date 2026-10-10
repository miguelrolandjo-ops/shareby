-- Shareby server schema (PostgreSQL 13+).
-- Safe to re-run: every statement is idempotent.
--
-- Sync model:
--   * IDs are UUIDs generated on the device, so records can be created offline.
--   * updated_at is the client's edit time and drives last-write-wins.
--   * server_updated_at is set by the server on every write and drives /sync/pull cursors.
--   * Deletes are soft (deleted_at) so other devices learn about them.

CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY,
  email         text NOT NULL UNIQUE,          -- stored lowercase
  display_name  text NOT NULL,
  provider      text NOT NULL,                 -- google | apple | dev
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
  token       text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS folders (
  id                 uuid PRIMARY KEY,
  owner_id           uuid NOT NULL REFERENCES users(id),
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

-- Invites for people who have not signed in yet; converted to members on first sign-in.
CREATE TABLE IF NOT EXISTS invitations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id    uuid NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  email        text NOT NULL,                  -- stored lowercase
  role         text NOT NULL CHECK (role IN ('editor', 'viewer')),
  invited_by   uuid NOT NULL REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  accepted_at  timestamptz,
  UNIQUE (folder_id, email)
);

CREATE TABLE IF NOT EXISTS items (
  id                   uuid PRIMARY KEY,
  owner_id             uuid NOT NULL REFERENCES users(id),   -- who saved / pinned it
  folder_id            uuid REFERENCES folders(id) ON DELETE SET NULL,  -- NULL = Uncategorized
  url                  text NOT NULL,
  title                text NOT NULL,
  source               text NOT NULL,          -- instagram | youtube | tiktok | web
  thumbnail_url        text,
  tag                  text,                   -- personal folders only (see trigger)
  status               text NOT NULL CHECK (status IN ('new', 'confirmed')),
  suggested_folder_id  uuid,
  confidence           real NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL,
  updated_at           timestamptz NOT NULL,
  deleted_at           timestamptz,
  server_updated_at    timestamptz NOT NULL DEFAULT now()
);

-- "Done" checkmark (v0.2). It has its own timestamp so it merges independently of
-- content edits: a friend ticking a pin and the author retitling it never clobber each other.
-- On shared boards it is shared by everyone; completed_by records who ticked it.
ALTER TABLE items ADD COLUMN IF NOT EXISTS completed_at          timestamptz;
ALTER TABLE items ADD COLUMN IF NOT EXISTS completed_by          uuid REFERENCES users(id);
ALTER TABLE items ADD COLUMN IF NOT EXISTS completion_updated_at timestamptz;

CREATE INDEX IF NOT EXISTS items_folder_idx      ON items (folder_id);
CREATE INDEX IF NOT EXISTS items_owner_idx       ON items (owner_id);
CREATE INDEX IF NOT EXISTS items_server_upd_idx  ON items (server_updated_at);
CREATE INDEX IF NOT EXISTS folders_server_upd_idx ON folders (server_updated_at);
CREATE INDEX IF NOT EXISTS members_user_idx      ON folder_members (user_id);
CREATE INDEX IF NOT EXISTS invitations_email_idx ON invitations (email) WHERE accepted_at IS NULL;

-- Product rule: tags and auto-categorization exist only for personal folders.
-- Enforced here as well as in the app, so no client can put a tag on a shared board.
CREATE OR REPLACE FUNCTION enforce_personal_tagging() RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS items_personal_tagging ON items;
CREATE TRIGGER items_personal_tagging
  BEFORE INSERT OR UPDATE ON items
  FOR EACH ROW EXECUTE FUNCTION enforce_personal_tagging();
