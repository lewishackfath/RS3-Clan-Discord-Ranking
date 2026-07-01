-- P3.4 Shared database / multi Discord guild isolation
-- Run this once before deploying the P3.4 code.
-- It scopes RuneScape rank mappings to both the clan and the Discord guild.

SET @current_database = DATABASE();

SELECT COUNT(*) INTO @has_discord_guild_id
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = @current_database
  AND TABLE_NAME = 'rs_rank_mappings'
  AND COLUMN_NAME = 'discord_guild_id';

SET @sql = IF(
    @has_discord_guild_id = 0,
    'ALTER TABLE rs_rank_mappings ADD COLUMN discord_guild_id VARCHAR(32) NULL AFTER clan_id',
    'SELECT "rs_rank_mappings.discord_guild_id already exists"'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE rs_rank_mappings mappings
JOIN guild_settings settings ON settings.clan_id = mappings.clan_id
SET mappings.discord_guild_id = settings.discord_guild_id
WHERE mappings.discord_guild_id IS NULL OR mappings.discord_guild_id = '';

UPDATE rs_rank_mappings
SET discord_guild_id = ''
WHERE discord_guild_id IS NULL;

DELETE duplicate_row
FROM rs_rank_mappings duplicate_row
JOIN rs_rank_mappings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.clan_id = kept_row.clan_id
 AND COALESCE(duplicate_row.discord_guild_id, '') = COALESCE(kept_row.discord_guild_id, '')
 AND duplicate_row.rs_rank_name = kept_row.rs_rank_name
 AND COALESCE(duplicate_row.discord_role_id, '') = COALESCE(kept_row.discord_role_id, '');

ALTER TABLE rs_rank_mappings
    MODIFY discord_guild_id VARCHAR(32) NOT NULL;

SELECT COUNT(*) INTO @has_old_unique
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = @current_database
  AND TABLE_NAME = 'rs_rank_mappings'
  AND INDEX_NAME = 'uq_rs_rank_mappings';

SET @sql = IF(
    @has_old_unique > 0,
    'ALTER TABLE rs_rank_mappings DROP INDEX uq_rs_rank_mappings',
    'SELECT "uq_rs_rank_mappings does not exist"'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO @has_role_unique
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = @current_database
  AND TABLE_NAME = 'rs_rank_mappings'
  AND INDEX_NAME = 'uq_rs_rank_mappings_role';

SET @sql = IF(
    @has_role_unique > 0,
    'ALTER TABLE rs_rank_mappings DROP INDEX uq_rs_rank_mappings_role',
    'SELECT "uq_rs_rank_mappings_role does not exist"'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO @has_rank_index
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = @current_database
  AND TABLE_NAME = 'rs_rank_mappings'
  AND INDEX_NAME = 'idx_rs_rank_mappings_rank';

SET @sql = IF(
    @has_rank_index > 0,
    'ALTER TABLE rs_rank_mappings DROP INDEX idx_rs_rank_mappings_rank',
    'SELECT "idx_rs_rank_mappings_rank does not exist"'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

ALTER TABLE rs_rank_mappings
    ADD KEY idx_rs_rank_mappings_rank (clan_id, discord_guild_id, rs_rank_name),
    ADD UNIQUE KEY uq_rs_rank_mappings_role (clan_id, discord_guild_id, rs_rank_name, discord_role_id);
