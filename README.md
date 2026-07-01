# RS3 Clan Discord Ranker

PHP/MySQL application for synchronising RuneScape clan ranks to Discord roles for one configured RuneScape clan and one configured Discord guild.

## Current model

This build is intentionally **single clan per database**.

- There is no `CLAN_ID` setting.
- The configured RuneScape clan comes from `CLAN_NAME` in `.env`.
- The configured Discord server comes from `DISCORD_GUILD_ID` in `.env`.
- Manual user mappings, nickname fallback matching, role mappings, sync preview, live sync, sync history, and automatic sync all operate against the local database only.
- The cron runner only checks the configured Discord guild from `.env`.

## Requirements

- PHP 8.1+
- `pdo_mysql`
- `curl`
- MySQL or MariaDB
- A Discord application with:
  - bot token
  - OAuth client ID / secret
  - redirect URI configured
  - the bot invited to the target guild

## Fresh install

1. Upload the project files.
2. Copy `.env.example` to `.env` and fill in your settings.
3. Import `sql/bootstrap.sql`.
4. The bootstrap is idempotent and replaces all previous migration files.
5. Log in, open **Discord Settings**, save the configured server settings, then import the clan roster from **Clan Members**.

## Upgrade from the shared-database build

If you previously had multiple clans sharing a database, split/copy the database first so this database contains only the intended clan.

Then back up the database and run the single bootstrap:

```bash
mysql -u DB_USER -p DB_NAME < sql/bootstrap.sql
```

After the bootstrap, remove `CLAN_ID` from `.env`. Keep `CLAN_NAME` and `DISCORD_GUILD_ID` configured.

## Main features

- Discord OAuth admin login
- Admin/user role checks via `.env`
- RuneScape clan roster import from `members_lite.ws`
- Read-only clan roster page sourced from RuneScape
- RuneScape rank to Discord role mappings
- Guest and Clan Member fallback mappings
- Manual Discord user to RSN mappings
- Runtime nickname fallback matching for unmapped Discord users
- Sync preview dry-run
- Live role sync with audit history
- Automatic sync via cron
- Discord log channel summaries and failure alerts
- Optional Guest DM when a member is moved to Guest fallback
- Discord role bootstrap for recommended roles

## Automatic sync cron example

```bash
*/5 * * * * /usr/bin/php /path/to/project/cron/cron_auto_sync.php >> /path/to/project/storage/logs/auto-sync.log 2>&1
```

The cron runner uses the same live sync engine as **Run Sync Now**.

## Notes

- Only manual user mappings are saved. Blank user selections remain runtime-only nickname fallback.
- Nickname matches are shown as previews in the admin UI and are never saved unless you choose a manual mapping.
- If your Discord guild is large, the User Mappings page may take longer because it reads guild members directly from Discord.
