-- Phase 3.6 migration
-- Converts an existing shared/multi-clan schema back to a single-clan-per-database schema.
-- Back up the database first. Run this after the database has been split so only the intended clan remains.

ALTER TABLE clan_members DROP INDEX IF EXISTS uq_clan_member_rsn;
ALTER TABLE clan_members DROP INDEX IF EXISTS idx_clan_members_clan_active;
ALTER TABLE clan_members DROP COLUMN IF EXISTS clan_id;
ALTER TABLE clan_members ADD UNIQUE KEY uq_clan_member_rsn (rsn_normalised);
ALTER TABLE clan_members ADD KEY idx_clan_members_active (is_active);

ALTER TABLE guild_settings DROP INDEX IF EXISTS uq_guild_settings_scope;
ALTER TABLE guild_settings DROP INDEX IF EXISTS uq_guild_settings_clan;
ALTER TABLE guild_settings DROP INDEX IF EXISTS uq_guild_settings_guild;
ALTER TABLE guild_settings DROP INDEX IF EXISTS idx_guild_settings_guild;
ALTER TABLE guild_settings DROP COLUMN IF EXISTS clan_id;
ALTER TABLE guild_settings ADD UNIQUE KEY uq_guild_settings_guild (discord_guild_id);

ALTER TABLE rs_rank_mappings DROP INDEX IF EXISTS uq_rs_rank_mappings;
ALTER TABLE rs_rank_mappings DROP INDEX IF EXISTS uq_rs_rank_mappings_role;
ALTER TABLE rs_rank_mappings DROP INDEX IF EXISTS idx_rs_rank_mappings_rank;
ALTER TABLE rs_rank_mappings DROP COLUMN IF EXISTS clan_id;
ALTER TABLE rs_rank_mappings ADD KEY idx_rs_rank_mappings_rank (discord_guild_id, rs_rank_name);
ALTER TABLE rs_rank_mappings ADD UNIQUE KEY uq_rs_rank_mappings_role (discord_guild_id, rs_rank_name, discord_role_id);

ALTER TABLE discord_user_mappings DROP INDEX IF EXISTS uq_discord_user_mappings;
ALTER TABLE discord_user_mappings DROP COLUMN IF EXISTS clan_id;
ALTER TABLE discord_user_mappings ADD UNIQUE KEY uq_discord_user_mappings (discord_guild_id, discord_user_id);

ALTER TABLE sync_runs DROP INDEX IF EXISTS idx_sync_runs_clan_id;
ALTER TABLE sync_runs DROP COLUMN IF EXISTS clan_id;
