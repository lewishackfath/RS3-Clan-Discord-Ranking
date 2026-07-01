-- P3.4 Shared database / multi Discord guild isolation
-- Run this once before deploying the P3.4 code.
--
-- cPanel-safe version: avoids information_schema because some restricted MySQL users
-- cannot query it. Re-running is safe; duplicate column/index and missing index
-- errors are ignored inside the migration procedure.

DROP PROCEDURE IF EXISTS migrate_p34_shared_database_guild_scoping;

DELIMITER //

CREATE PROCEDURE migrate_p34_shared_database_guild_scoping()
BEGIN
    -- Add guild scope column when it does not already exist.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1060 BEGIN END; -- Duplicate column name
        ALTER TABLE rs_rank_mappings
            ADD COLUMN discord_guild_id VARCHAR(32) NULL AFTER clan_id;
    END;

    -- Backfill existing mappings from guild_settings where possible.
    -- If more than one guild_settings row exists for the same clan_id, this uses the
    -- lowest id row as the safest deterministic default. After migration, review any
    -- shared clan_id mappings and recreate per-guild mappings if required.
    UPDATE rs_rank_mappings mappings
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

    UPDATE rs_rank_mappings
    SET discord_guild_id = ''
    WHERE discord_guild_id IS NULL;

    -- Remove duplicates before creating the new scoped unique key.
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

    -- Drop old indexes if they exist.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END; -- Can't DROP; check that column/key exists
        ALTER TABLE rs_rank_mappings DROP INDEX uq_rs_rank_mappings;
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END;
        ALTER TABLE rs_rank_mappings DROP INDEX uq_rs_rank_mappings_role;
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1091 BEGIN END;
        ALTER TABLE rs_rank_mappings DROP INDEX idx_rs_rank_mappings_rank;
    END;

    -- Add the new guild-scoped indexes. Ignore duplicate index errors so the
    -- migration can be re-run safely.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1061 BEGIN END; -- Duplicate key name
        ALTER TABLE rs_rank_mappings
            ADD KEY idx_rs_rank_mappings_rank (clan_id, discord_guild_id, rs_rank_name);
    END;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1061 BEGIN END;
        ALTER TABLE rs_rank_mappings
            ADD UNIQUE KEY uq_rs_rank_mappings_role (clan_id, discord_guild_id, rs_rank_name, discord_role_id);
    END;
END//

DELIMITER ;

CALL migrate_p34_shared_database_guild_scoping();

DROP PROCEDURE IF EXISTS migrate_p34_shared_database_guild_scoping;
