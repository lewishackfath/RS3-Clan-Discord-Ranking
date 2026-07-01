-- P3.5 one-time fallback for hosts that do not allow stored procedures.
-- Only run this after a backup, and only run it once.

DELETE duplicate_row
FROM guild_settings duplicate_row
JOIN guild_settings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.clan_id = kept_row.clan_id
 AND duplicate_row.discord_guild_id = kept_row.discord_guild_id;

ALTER TABLE guild_settings DROP INDEX uq_guild_settings_clan;
ALTER TABLE guild_settings DROP INDEX uq_guild_settings_guild;
ALTER TABLE guild_settings ADD UNIQUE KEY uq_guild_settings_scope (clan_id, discord_guild_id);
ALTER TABLE guild_settings ADD KEY idx_guild_settings_guild (discord_guild_id);

ALTER TABLE discord_user_mappings ADD COLUMN discord_guild_id VARCHAR(32) NULL AFTER clan_id;

UPDATE discord_user_mappings mappings
JOIN (
    SELECT gs.clan_id, gs.discord_guild_id
    FROM guild_settings gs
    JOIN (
        SELECT clan_id, MIN(id) AS id
        FROM guild_settings
        GROUP BY clan_id
    ) chosen ON chosen.id = gs.id
) settings ON settings.clan_id = mappings.clan_id
SET mappings.discord_guild_id = settings.discord_guild_id
WHERE mappings.discord_guild_id IS NULL OR mappings.discord_guild_id = '';

UPDATE discord_user_mappings
SET discord_guild_id = ''
WHERE discord_guild_id IS NULL;

DELETE duplicate_row
FROM discord_user_mappings duplicate_row
JOIN discord_user_mappings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.clan_id = kept_row.clan_id
 AND COALESCE(duplicate_row.discord_guild_id, '') = COALESCE(kept_row.discord_guild_id, '')
 AND duplicate_row.discord_user_id = kept_row.discord_user_id;

ALTER TABLE discord_user_mappings MODIFY discord_guild_id VARCHAR(32) NOT NULL;
ALTER TABLE discord_user_mappings DROP INDEX uq_discord_user_mappings;
ALTER TABLE discord_user_mappings ADD UNIQUE KEY uq_discord_user_mappings (clan_id, discord_guild_id, discord_user_id);
