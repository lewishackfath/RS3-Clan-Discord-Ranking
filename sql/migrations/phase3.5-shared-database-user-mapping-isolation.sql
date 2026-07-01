-- P3.5 Shared database / user mapping isolation
-- Run this after P3.4 on shared database installs.
--
-- This migration avoids information_schema because restricted cPanel MySQL users
-- may not be able to query it. Re-running is safe; duplicate column/index and
-- missing index errors are ignored inside the migration procedure.

DROP PROCEDURE IF EXISTS migrate_p35_shared_database_user_mapping_isolation;

DELIMITER //

CREATE PROCEDURE migrate_p35_shared_database_user_mapping_isolation()
BEGIN
    -- Allow multiple Discord guild settings rows for the same RuneScape clan,
    -- and allow the same Discord guild to be used by more than one clan where needed.
    DELETE duplicate_row
    FROM guild_settings duplicate_row
    JOIN guild_settings kept_row
      ON duplicate_row.id > kept_row.id
     AND duplicate_row.clan_id = kept_row.clan_id
     AND duplicate_row.discord_guild_id = kept_row.discord_guild_id;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END; -- Can't DROP; check that column/key exists
        ALTER TABLE guild_settings DROP INDEX uq_guild_settings_clan;
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END;
        ALTER TABLE guild_settings DROP INDEX uq_guild_settings_guild;
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1061 BEGIN END; -- Duplicate key name
        ALTER TABLE guild_settings
            ADD UNIQUE KEY uq_guild_settings_scope (clan_id, discord_guild_id);
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1061 BEGIN END;
        ALTER TABLE guild_settings
            ADD KEY idx_guild_settings_guild (discord_guild_id);
    END;

    -- Make sure manual Discord user mappings are guild-scoped even on older installs.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1060 BEGIN END; -- Duplicate column name
        ALTER TABLE discord_user_mappings
            ADD COLUMN discord_guild_id VARCHAR(32) NULL AFTER clan_id;
    END;

    -- Backfill older user mappings from their clan's guild settings where possible.
    -- If more than one guild_settings row exists for the same clan_id, this uses the
    -- lowest id row as a deterministic fallback. Re-save affected mappings from the
    -- User Mappings page if the old row belonged to a different guild.
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

    -- Remove duplicate rows that would block the new scoped unique key.
    DELETE duplicate_row
    FROM discord_user_mappings duplicate_row
    JOIN discord_user_mappings kept_row
      ON duplicate_row.id > kept_row.id
     AND duplicate_row.clan_id = kept_row.clan_id
     AND COALESCE(duplicate_row.discord_guild_id, '') = COALESCE(kept_row.discord_guild_id, '')
     AND duplicate_row.discord_user_id = kept_row.discord_user_id;

    ALTER TABLE discord_user_mappings
        MODIFY discord_guild_id VARCHAR(32) NOT NULL;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END;
        ALTER TABLE discord_user_mappings DROP INDEX uq_discord_user_mappings;
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1061 BEGIN END;
        ALTER TABLE discord_user_mappings
            ADD UNIQUE KEY uq_discord_user_mappings (clan_id, discord_guild_id, discord_user_id);
    END;
END//

DELIMITER ;

CALL migrate_p35_shared_database_user_mapping_isolation();

DROP PROCEDURE IF EXISTS migrate_p35_shared_database_user_mapping_isolation;
