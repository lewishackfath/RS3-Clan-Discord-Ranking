-- RS3 Clan Discord Ranker database bootstrap
-- Single-clan-per-database schema.
--
-- Safe to run for fresh installs and upgrades from the older migration-based builds.
-- This bootstrap intentionally avoids information_schema for restricted cPanel users.
-- Back up existing databases before running any schema cleanup.

SET FOREIGN_KEY_CHECKS = 0;

-- No retired app-owned tables are currently required to be dropped.
-- The old shared-database model used clan_id columns/indexes rather than separate tables.
-- Those columns/indexes are cleaned up below.

CREATE TABLE IF NOT EXISTS clan_members (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    rsn VARCHAR(32) NOT NULL,
    rsn_normalised VARCHAR(32) NOT NULL,
    rank_name VARCHAR(64) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_clan_member_rsn (rsn_normalised),
    KEY idx_clan_members_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS guild_settings (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    discord_guild_id VARCHAR(32) NOT NULL,
    guild_name_cache VARCHAR(255) NULL,
    bot_user_id VARCHAR(32) NULL,
    bot_role_id VARCHAR(32) NULL,
    bot_role_name_cache VARCHAR(255) NULL,
    last_validation_at DATETIME NULL,
    validation_status VARCHAR(32) NULL,
    validation_message TEXT NULL,
    log_channel_id VARCHAR(32) NULL,
    log_channel_name_cache VARCHAR(255) NULL,
    send_guest_dm TINYINT(1) NOT NULL DEFAULT 0,
    guest_dm_message TEXT NULL,
    auto_sync_enabled TINYINT(1) NOT NULL DEFAULT 0,
    auto_sync_interval_minutes INT NOT NULL DEFAULT 15,
    last_auto_sync_at DATETIME NULL,
    last_roster_import_at DATETIME NULL,
    last_roster_import_status VARCHAR(32) NULL,
    last_roster_import_message TEXT NULL,
    last_auto_sync_status VARCHAR(32) NULL,
    last_auto_sync_message TEXT NULL,
    server_admin_role_id VARCHAR(32) NULL,
    server_admin_role_name_cache VARCHAR(255) NULL,
    server_moderator_role_id VARCHAR(32) NULL,
    server_moderator_role_name_cache VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_guild_settings_guild (discord_guild_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS rs_rank_mappings (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    discord_guild_id VARCHAR(32) NOT NULL,
    rs_rank_name VARCHAR(64) NOT NULL,
    discord_role_id VARCHAR(32) NULL,
    discord_role_name_cache VARCHAR(255) NULL,
    is_enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_rs_rank_mappings_rank (discord_guild_id, rs_rank_name),
    UNIQUE KEY uq_rs_rank_mappings_role (discord_guild_id, rs_rank_name, discord_role_id),
    KEY idx_rs_rank_mappings_role (discord_role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS discord_role_flags (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    discord_guild_id VARCHAR(32) NOT NULL,
    discord_role_id VARCHAR(32) NOT NULL,
    role_name_cache VARCHAR(255) NULL,
    position_cache INT NULL,
    is_bot_role TINYINT(1) NOT NULL DEFAULT 0,
    is_protected_role TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_discord_role_flags (discord_guild_id, discord_role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS discord_user_mappings (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    discord_guild_id VARCHAR(32) NOT NULL,
    discord_user_id VARCHAR(32) NOT NULL,
    member_id BIGINT UNSIGNED NOT NULL,
    rsn_cache VARCHAR(32) NOT NULL,
    discord_username_cache VARCHAR(255) NULL,
    discord_nickname_cache VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_discord_user_mappings (discord_guild_id, discord_user_id),
    KEY idx_discord_user_mappings_member (member_id),
    CONSTRAINT fk_discord_user_mappings_member
        FOREIGN KEY (member_id) REFERENCES clan_members(id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sync_runs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    discord_guild_id VARCHAR(32) NOT NULL,
    initiated_by_discord_user_id VARCHAR(32) NULL,
    initiated_by_name VARCHAR(255) NULL,
    trigger_source VARCHAR(20) NOT NULL DEFAULT 'manual',
    status VARCHAR(50) NOT NULL DEFAULT 'running',
    started_at_utc DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    finished_at_utc DATETIME(3) NULL,
    total_members INT NOT NULL DEFAULT 0,
    changed_members INT NOT NULL DEFAULT 0,
    skipped_members INT NOT NULL DEFAULT 0,
    blocked_members INT NOT NULL DEFAULT 0,
    error_members INT NOT NULL DEFAULT 0,
    summary_text TEXT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    KEY idx_sync_runs_discord_guild_id (discord_guild_id),
    KEY idx_sync_runs_trigger_source (trigger_source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sync_run_members (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    sync_run_id BIGINT UNSIGNED NOT NULL,
    discord_user_id VARCHAR(32) NOT NULL,
    discord_username VARCHAR(255) NULL,
    discord_display_name VARCHAR(255) NULL,
    resolved_rsn VARCHAR(255) NULL,
    resolved_rank_name VARCHAR(100) NULL,
    resolved_by VARCHAR(100) NULL,
    status VARCHAR(50) NOT NULL,
    added_role_ids_csv TEXT NULL,
    removed_role_ids_csv TEXT NULL,
    blocked_role_ids_csv TEXT NULL,
    guest_dm_attempted TINYINT(1) NOT NULL DEFAULT 0,
    guest_dm_success TINYINT(1) NOT NULL DEFAULT 0,
    guest_dm_error TEXT NULL,
    notes TEXT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    KEY idx_sync_run_members_sync_run_id (sync_run_id),
    KEY idx_sync_run_members_discord_user_id (discord_user_id),
    CONSTRAINT fk_sync_run_members_sync_run
        FOREIGN KEY (sync_run_id) REFERENCES sync_runs(id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Bring older tables up to the current column set.
ALTER TABLE clan_members
    ADD COLUMN IF NOT EXISTS rsn VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS rsn_normalised VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS rank_name VARCHAR(64) NULL,
    ADD COLUMN IF NOT EXISTS is_active TINYINT(1) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE guild_settings
    ADD COLUMN IF NOT EXISTS discord_guild_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS guild_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS bot_user_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS bot_role_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS bot_role_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS last_validation_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS validation_status VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS validation_message TEXT NULL,
    ADD COLUMN IF NOT EXISTS log_channel_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS log_channel_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS send_guest_dm TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS guest_dm_message TEXT NULL,
    ADD COLUMN IF NOT EXISTS auto_sync_enabled TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS auto_sync_interval_minutes INT NOT NULL DEFAULT 15,
    ADD COLUMN IF NOT EXISTS last_auto_sync_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS last_roster_import_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS last_roster_import_status VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS last_roster_import_message TEXT NULL,
    ADD COLUMN IF NOT EXISTS last_auto_sync_status VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS last_auto_sync_message TEXT NULL,
    ADD COLUMN IF NOT EXISTS server_admin_role_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS server_admin_role_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS server_moderator_role_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS server_moderator_role_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE rs_rank_mappings
    ADD COLUMN IF NOT EXISTS discord_guild_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS rs_rank_name VARCHAR(64) NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_role_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS discord_role_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS is_enabled TINYINT(1) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE discord_role_flags
    ADD COLUMN IF NOT EXISTS discord_guild_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_role_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS role_name_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS position_cache INT NULL,
    ADD COLUMN IF NOT EXISTS is_bot_role TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_protected_role TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE discord_user_mappings
    ADD COLUMN IF NOT EXISTS discord_guild_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS discord_user_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS member_id BIGINT UNSIGNED NOT NULL,
    ADD COLUMN IF NOT EXISTS rsn_cache VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_username_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS discord_nickname_cache VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE sync_runs
    ADD COLUMN IF NOT EXISTS discord_guild_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS initiated_by_discord_user_id VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS initiated_by_name VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS trigger_source VARCHAR(20) NOT NULL DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL DEFAULT 'running',
    ADD COLUMN IF NOT EXISTS started_at_utc DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS finished_at_utc DATETIME(3) NULL,
    ADD COLUMN IF NOT EXISTS total_members INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS changed_members INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS skipped_members INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS blocked_members INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS error_members INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS summary_text TEXT NULL,
    ADD COLUMN IF NOT EXISTS created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);

ALTER TABLE sync_run_members
    ADD COLUMN IF NOT EXISTS sync_run_id BIGINT UNSIGNED NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_user_id VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_username VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS discord_display_name VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS resolved_rsn VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS resolved_rank_name VARCHAR(100) NULL,
    ADD COLUMN IF NOT EXISTS resolved_by VARCHAR(100) NULL,
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL,
    ADD COLUMN IF NOT EXISTS added_role_ids_csv TEXT NULL,
    ADD COLUMN IF NOT EXISTS removed_role_ids_csv TEXT NULL,
    ADD COLUMN IF NOT EXISTS blocked_role_ids_csv TEXT NULL,
    ADD COLUMN IF NOT EXISTS guest_dm_attempted TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS guest_dm_success TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS guest_dm_error TEXT NULL,
    ADD COLUMN IF NOT EXISTS notes TEXT NULL,
    ADD COLUMN IF NOT EXISTS created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);

-- Backfill guild scope for installs that previously keyed role mappings only by clan_id.
UPDATE rs_rank_mappings mappings
JOIN (
    SELECT discord_guild_id
    FROM guild_settings
    WHERE discord_guild_id IS NOT NULL AND discord_guild_id <> ''
    ORDER BY id ASC
    LIMIT 1
) settings
SET mappings.discord_guild_id = settings.discord_guild_id
WHERE mappings.discord_guild_id IS NULL OR mappings.discord_guild_id = '';

UPDATE discord_user_mappings mappings
JOIN (
    SELECT discord_guild_id
    FROM guild_settings
    WHERE discord_guild_id IS NOT NULL AND discord_guild_id <> ''
    ORDER BY id ASC
    LIMIT 1
) settings
SET mappings.discord_guild_id = settings.discord_guild_id
WHERE mappings.discord_guild_id IS NULL OR mappings.discord_guild_id = '';

-- Remove rows that cannot be used by the current single-guild runtime.
DELETE FROM rs_rank_mappings WHERE discord_guild_id IS NULL OR discord_guild_id = '';
DELETE FROM discord_user_mappings WHERE discord_guild_id IS NULL OR discord_guild_id = '';

-- De-duplicate exact rows before final unique keys are recreated.
DELETE duplicate_row
FROM guild_settings duplicate_row
JOIN guild_settings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.discord_guild_id = kept_row.discord_guild_id;

DELETE duplicate_row
FROM rs_rank_mappings duplicate_row
JOIN rs_rank_mappings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.discord_guild_id = kept_row.discord_guild_id
 AND duplicate_row.rs_rank_name = kept_row.rs_rank_name
 AND COALESCE(duplicate_row.discord_role_id, '') = COALESCE(kept_row.discord_role_id, '');

DELETE duplicate_row
FROM discord_user_mappings duplicate_row
JOIN discord_user_mappings kept_row
  ON duplicate_row.id > kept_row.id
 AND duplicate_row.discord_guild_id = kept_row.discord_guild_id
 AND duplicate_row.discord_user_id = kept_row.discord_user_id;

-- Remove legacy shared-database columns and indexes.
ALTER TABLE clan_members
    DROP INDEX IF EXISTS uq_clan_member_rsn,
    DROP INDEX IF EXISTS idx_clan_members_clan_active,
    DROP INDEX IF EXISTS idx_clan_members_active,
    DROP COLUMN IF EXISTS clan_id,
    ADD UNIQUE KEY uq_clan_member_rsn (rsn_normalised),
    ADD KEY idx_clan_members_active (is_active);

ALTER TABLE guild_settings
    DROP INDEX IF EXISTS uq_guild_settings_scope,
    DROP INDEX IF EXISTS uq_guild_settings_clan,
    DROP INDEX IF EXISTS uq_guild_settings_guild,
    DROP INDEX IF EXISTS idx_guild_settings_guild,
    DROP COLUMN IF EXISTS clan_id,
    ADD UNIQUE KEY uq_guild_settings_guild (discord_guild_id);

ALTER TABLE rs_rank_mappings
    DROP INDEX IF EXISTS uq_rs_rank_mappings,
    DROP INDEX IF EXISTS uq_rs_rank_mappings_role,
    DROP INDEX IF EXISTS idx_rs_rank_mappings_rank,
    DROP INDEX IF EXISTS idx_rs_rank_mappings_role,
    DROP COLUMN IF EXISTS clan_id,
    MODIFY discord_guild_id VARCHAR(32) NOT NULL,
    ADD KEY idx_rs_rank_mappings_rank (discord_guild_id, rs_rank_name),
    ADD UNIQUE KEY uq_rs_rank_mappings_role (discord_guild_id, rs_rank_name, discord_role_id),
    ADD KEY idx_rs_rank_mappings_role (discord_role_id);

ALTER TABLE discord_role_flags
    DROP INDEX IF EXISTS uq_discord_role_flags,
    ADD UNIQUE KEY uq_discord_role_flags (discord_guild_id, discord_role_id);

ALTER TABLE discord_user_mappings
    DROP INDEX IF EXISTS uq_discord_user_mappings,
    DROP COLUMN IF EXISTS clan_id,
    MODIFY discord_guild_id VARCHAR(32) NOT NULL,
    ADD UNIQUE KEY uq_discord_user_mappings (discord_guild_id, discord_user_id);

ALTER TABLE sync_runs
    DROP INDEX IF EXISTS idx_sync_runs_clan_id,
    DROP INDEX IF EXISTS idx_sync_runs_discord_guild_id,
    DROP INDEX IF EXISTS idx_sync_runs_trigger_source,
    DROP COLUMN IF EXISTS clan_id,
    ADD KEY idx_sync_runs_discord_guild_id (discord_guild_id),
    ADD KEY idx_sync_runs_trigger_source (trigger_source);


-- Seed default rank rows for any configured guild settings row that does not already have them.
INSERT INTO rs_rank_mappings (discord_guild_id, rs_rank_name, discord_role_id, discord_role_name_cache, is_enabled)
SELECT settings.discord_guild_id, ranks.rs_rank_name, NULL, NULL, 1
FROM guild_settings settings
JOIN (
    SELECT 'Guest' AS rs_rank_name UNION ALL
    SELECT 'Clan Member' UNION ALL
    SELECT 'Recruit' UNION ALL
    SELECT 'Corporal' UNION ALL
    SELECT 'Sergeant' UNION ALL
    SELECT 'Lieutenant' UNION ALL
    SELECT 'Captain' UNION ALL
    SELECT 'General' UNION ALL
    SELECT 'Admin' UNION ALL
    SELECT 'Organiser' UNION ALL
    SELECT 'Coordinator' UNION ALL
    SELECT 'Overseer' UNION ALL
    SELECT 'Deputy Owner' UNION ALL
    SELECT 'Owner'
) ranks
WHERE settings.discord_guild_id IS NOT NULL
  AND settings.discord_guild_id <> ''
  AND NOT EXISTS (
      SELECT 1
      FROM rs_rank_mappings existing
      WHERE existing.discord_guild_id = settings.discord_guild_id
        AND existing.rs_rank_name = ranks.rs_rank_name
  );

SET FOREIGN_KEY_CHECKS = 1;
