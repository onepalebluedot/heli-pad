export const schema = `
CREATE TABLE IF NOT EXISTS helipad_account (
    id UUID PRIMARY KEY,
    apple_subject TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL DEFAULT '',
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS helipad_auth_challenge (
    nonce_hash TEXT PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS helipad_session (
    token_hash TEXT PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES helipad_account(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS helipad_family (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS helipad_family_member (
    family_id UUID NOT NULL REFERENCES helipad_family(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES helipad_account(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, account_id)
);

CREATE TABLE IF NOT EXISTS helipad_family_invite (
    code_hash TEXT PRIMARY KEY,
    family_id UUID NOT NULL REFERENCES helipad_family(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES helipad_account(id),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_by UUID REFERENCES helipad_account(id),
    accepted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS helipad_family_document (
    family_id UUID NOT NULL REFERENCES helipad_family(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('household', 'lists')),
    state_data JSONB NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, kind)
);

CREATE TABLE IF NOT EXISTS helipad_alpha_signup (
    email TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS helipad_session_account_idx ON helipad_session(account_id);
CREATE INDEX IF NOT EXISTS helipad_family_invite_family_idx ON helipad_family_invite(family_id);
`;
