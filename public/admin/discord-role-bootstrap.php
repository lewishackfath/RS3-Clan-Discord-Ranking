<?php
declare(strict_types=1);
require_once __DIR__ . '/../../app/config/bootstrap.php';
require_login();

$pdo = db();
$guildId = (string)env('DISCORD_GUILD_ID', '');
$clanId = (int)env('CLAN_ID', '1');

$missingTables = require_tables($pdo, ['guild_settings', 'rs_rank_mappings']);
$guildSettings = [];
$guild = null;
$discordRoles = [];
$scanError = null;

const DISCORD_PERMISSION_ADMINISTRATOR = '8';
const DISCORD_PERMISSION_SERVER_MODERATOR = '1099511644166'; // Kick + Ban + Manage Messages + Moderate Members

function bootstrap_recommended_roles(): array
{
    return [
        ['name' => 'Server Admin', 'permission_mode' => 'administrator', 'permissions' => DISCORD_PERMISSION_ADMINISTRATOR, 'description' => 'Administrator access for trusted server admins.'],
        ['name' => 'Server Moderator', 'permission_mode' => 'moderator', 'permissions' => DISCORD_PERMISSION_SERVER_MODERATOR, 'description' => 'Kick, ban, timeout, and manage messages without role/server settings management.'],
        ['name' => 'Owner', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Deputy Owner', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Overseer', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Coordinator', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Admin', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended Discord equivalent for the RuneScape Admin rank.'],
        ['name' => 'General', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Captain', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Lieutenant', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Sergeant', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Corporal', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Recruit', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Recommended clan hierarchy role.'],
        ['name' => 'Clan Member', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Base member role used by sync mappings.'],
        ['name' => 'Guest', 'permission_mode' => 'none', 'permissions' => null, 'description' => 'Fallback guest role used by sync mappings.'],
    ];
}

function bootstrap_role_index_by_name(array $roles): array
{
    $index = [];
    foreach ($roles as $role) {
        if (!is_array($role)) {
            continue;
        }
        $name = trim((string)($role['name'] ?? ''));
        if ($name === '' || $name === '@everyone') {
            continue;
        }
        if (!isset($index[$name])) {
            $index[$name] = $role;
        }
    }
    return $index;
}

function bootstrap_role_candidate_names(string $roleName): array
{
    $candidates = [];

    $push = static function (string $value) use (&$candidates): void {
        $value = trim($value);
        if ($value === '') {
            return;
        }
        if (!in_array($value, $candidates, true)) {
            $candidates[] = $value;
        }
    };

    $push($roleName);

    if (preg_match('/y$/i', $roleName) === 1) {
        $push(substr($roleName, 0, -1) . 'ies');
    } elseif (preg_match('/(s|x|z|ch|sh)$/i', $roleName) === 1) {
        $push($roleName . 'es');
    } else {
        $push($roleName . 's');
    }

    return $candidates;
}

function bootstrap_find_matching_role(array $rolesByName, string $roleName): ?array
{
    foreach (bootstrap_role_candidate_names($roleName) as $candidateName) {
        if (isset($rolesByName[$candidateName]) && is_array($rolesByName[$candidateName])) {
            return $rolesByName[$candidateName];
        }
    }

    return null;
}


function bootstrap_find_role_by_bot_id(array $roles, string $botUserId): ?array
{
    foreach ($roles as $role) {
        if (!is_array($role)) {
            continue;
        }
        $roleBotId = (string)($role['tags']['bot_id'] ?? '');
        if ($roleBotId !== '' && $roleBotId === $botUserId) {
            return $role;
        }
    }

    return null;
}

function bootstrap_reorder_admin_roles_beneath_bot(string $guildId, array $roles, string $botUserId): array
{
    $botRole = bootstrap_find_role_by_bot_id($roles, $botUserId);
    if ($botRole === null) {
        throw new RuntimeException('Unable to locate the bot managed role for hierarchy placement.');
    }

    $roleMap = discord_role_map($roles);
    $serverAdminRole = bootstrap_find_matching_role(bootstrap_role_index_by_name($roles), 'Server Admin');
    $serverModeratorRole = bootstrap_find_matching_role(bootstrap_role_index_by_name($roles), 'Server Moderator');

    if ($serverAdminRole === null || $serverModeratorRole === null) {
        throw new RuntimeException('Server Admin and Server Moderator must exist before role ordering can be applied.');
    }

    $everyoneRoleId = null;
    foreach ($roles as $role) {
        if (!is_array($role)) {
            continue;
        }
        if ((string)($role['name'] ?? '') === '@everyone') {
            $everyoneRoleId = (string)($role['id'] ?? '');
            break;
        }
    }

    $sortableRoles = [];
    foreach ($roles as $role) {
        if (!is_array($role)) {
            continue;
        }
        $roleId = (string)($role['id'] ?? '');
        if ($roleId === '' || $roleId === $everyoneRoleId) {
            continue;
        }
        $sortableRoles[] = $role;
    }

    usort($sortableRoles, static function (array $a, array $b): int {
        $aPos = (int)($a['position'] ?? 0);
        $bPos = (int)($b['position'] ?? 0);
        if ($aPos !== $bPos) {
            return $bPos <=> $aPos;
        }
        return strcmp((string)($a['id'] ?? ''), (string)($b['id'] ?? ''));
    });

    $pinnedRoleIds = array_values(array_unique([
        (string)$botRole['id'],
        (string)$serverAdminRole['id'],
        (string)$serverModeratorRole['id'],
    ]));

    $remainingRoles = [];
    foreach ($sortableRoles as $role) {
        $roleId = (string)($role['id'] ?? '');
        if (in_array($roleId, $pinnedRoleIds, true)) {
            continue;
        }
        $remainingRoles[] = $role;
    }

    $finalRoles = [
        $roleMap[(string)$botRole['id']],
        $roleMap[(string)$serverAdminRole['id']],
        $roleMap[(string)$serverModeratorRole['id']],
    ];
    foreach ($remainingRoles as $role) {
        $finalRoles[] = $role;
    }

    $positions = [];
    $positionValue = count($finalRoles);
    foreach ($finalRoles as $role) {
        $positions[] = [
            'id' => (string)$role['id'],
            'position' => $positionValue,
        ];
        $positionValue--;
    }

    discord_reorder_roles($guildId, $positions);

    return [
        'bot_role_name' => (string)($botRole['name'] ?? ''),
        'server_admin_role_name' => (string)($serverAdminRole['name'] ?? ''),
        'server_moderator_role_name' => (string)($serverModeratorRole['name'] ?? ''),
    ];
}

function bootstrap_admin_user_ids_from_env(): array
{
    $raw = (string)env('ADMIN_DISCORD_USER_IDS', '');
    if ($raw === '') {
        return [];
    }

    $parts = preg_split('/[\s,]+/', $raw) ?: [];
    $ids = [];
    foreach ($parts as $part) {
        $part = trim((string)$part);
        if ($part === '' || !preg_match('/^\d+$/', $part)) {
            continue;
        }
        $ids[] = $part;
    }

    return array_values(array_unique($ids));
}

function bootstrap_assign_server_admin_role_to_env_admins(string $guildId, string $serverAdminRoleId, array $adminUserIds): array
{
    $applied = [];

    foreach ($adminUserIds as $userId) {
        $userId = trim((string)$userId);
        if ($userId === '') {
            continue;
        }

        $member = discord_get_guild_member($guildId, $userId);
        if ($member === null) {
            continue;
        }

        $currentRoles = array_map('strval', $member['roles'] ?? []);
        if (in_array($serverAdminRoleId, $currentRoles, true)) {
            continue;
        }

        $currentRoles[] = $serverAdminRoleId;
        discord_modify_member_roles($guildId, $userId, $currentRoles);
        $applied[] = $userId;
    }

    return $applied;
}

function bootstrap_existing_rank_mappings(PDO $pdo, int $clanId): array
{
    $stmt = $pdo->prepare('SELECT rs_rank_name, discord_role_id, discord_role_name_cache, is_enabled
        FROM rs_rank_mappings
        WHERE clan_id = :clan_id
        ORDER BY rs_rank_name ASC, id ASC');
    $stmt->execute(['clan_id' => $clanId]);

    $out = [];
    foreach ($stmt->fetchAll() as $row) {
        $rankName = (string)($row['rs_rank_name'] ?? '');
        if ($rankName === '') {
            continue;
        }
        if (!isset($out[$rankName])) {
            $out[$rankName] = [
                'role_ids' => [],
                'role_names' => [],
                'is_enabled' => (int)($row['is_enabled'] ?? 1) === 1 ? 1 : 0,
            ];
        }

        $roleId = trim((string)($row['discord_role_id'] ?? ''));
        if ($roleId !== '') {
            $out[$rankName]['role_ids'][] = $roleId;
            $out[$rankName]['role_names'][] = (string)($row['discord_role_name_cache'] ?? '');
        }

        if ((int)($row['is_enabled'] ?? 0) === 1) {
            $out[$rankName]['is_enabled'] = 1;
        }
    }

    return $out;
}

function bootstrap_default_rank_targets(): array
{
    return [
        'Guest' => 'Guest',
        'Clan Member' => 'Clan Member',
        'Recruit' => 'Recruit',
        'Corporal' => 'Corporal',
        'Sergeant' => 'Sergeant',
        'Lieutenant' => 'Lieutenant',
        'Captain' => 'Captain',
        'General' => 'General',
        'Admin' => 'Admin',
        'Coordinator' => 'Coordinator',
        'Overseer' => 'Overseer',
        'Deputy Owner' => 'Deputy Owner',
        'Owner' => 'Owner',
    ];
}

function bootstrap_scan_plan(array $recommendedRoles, array $rolesByName, array $guildSettings, array $rankMappings): array
{
    $roleRows = [];
    $missingRoleNames = [];
    foreach ($recommendedRoles as $definition) {
        $name = (string)$definition['name'];
        $existing = bootstrap_find_matching_role($rolesByName, $name);
        $roleRows[] = [
            'name' => $name,
            'permission_mode' => (string)$definition['permission_mode'],
            'description' => (string)$definition['description'],
            'existing' => $existing,
            'will_create' => $existing === null,
        ];
        if ($existing === null) {
            $missingRoleNames[] = $name;
        }
    }

    $settingTargets = [
        'server_admin_role_id' => 'Server Admin',
        'server_moderator_role_id' => 'Server Moderator',
    ];

    $settingRows = [];
    foreach ($settingTargets as $column => $roleName) {
        $currentRoleId = trim((string)($guildSettings[$column] ?? ''));
        $matchedRole = bootstrap_find_matching_role($rolesByName, $roleName);
        $settingRows[] = [
            'column' => $column,
            'label' => $roleName,
            'current_role_id' => $currentRoleId,
            'matched_role' => $matchedRole,
            'will_fill' => $currentRoleId === '' && $matchedRole !== null,
        ];
    }

    $mappingRows = [];
    foreach (bootstrap_default_rank_targets() as $rankName => $roleName) {
        $current = $rankMappings[$rankName] ?? ['role_ids' => [], 'role_names' => [], 'is_enabled' => 1];
        $matchedRole = bootstrap_find_matching_role($rolesByName, $roleName);
        $hasExactTarget = $matchedRole !== null && in_array((string)$matchedRole['id'], array_map('strval', $current['role_ids']), true);

        $mappingRows[] = [
            'rank_name' => $rankName,
            'target_role_name' => $roleName,
            'matched_role' => $matchedRole,
            'current_role_names' => array_values(array_filter(array_map('strval', $current['role_names']))),
            'will_fill' => $matchedRole !== null && !$hasExactTarget && empty($current['role_ids']),
        ];
    }

    return [
        'roles' => $roleRows,
        'missing_role_names' => $missingRoleNames,
        'settings' => $settingRows,
        'mappings' => $mappingRows,
    ];
}

if (!$missingTables) {
    try {
        $guild = discord_get_guild($guildId);
        $discordRoles = discord_get_guild_roles($guildId);

        $settingsStmt = $pdo->prepare('SELECT * FROM guild_settings WHERE clan_id = :clan_id LIMIT 1');
        $settingsStmt->execute(['clan_id' => $clanId]);
        $guildSettings = $settingsStmt->fetch() ?: [];
    } catch (Throwable $e) {
        $scanError = $e->getMessage();
    }
}

$rolesByName = bootstrap_role_index_by_name($discordRoles);
$rankMappings = (!$missingTables && $scanError === null) ? bootstrap_existing_rank_mappings($pdo, $clanId) : [];
$recommendedRoles = bootstrap_recommended_roles();
$scanPlan = (!$missingTables && $scanError === null) ? bootstrap_scan_plan($recommendedRoles, $rolesByName, $guildSettings, $rankMappings) : [
    'roles' => [],
    'missing_role_names' => [],
    'settings' => [],
    'mappings' => [],
];

if (!$missingTables && $scanError === null && $_SERVER['REQUEST_METHOD'] === 'POST') {
    verify_csrf_or_fail();
    $action = (string)($_POST['action'] ?? '');

    if ($action === 'deploy_bootstrap') {
        try {
            $guild = discord_get_guild($guildId);
            $discordRoles = discord_get_guild_roles($guildId);
            $rolesByName = bootstrap_role_index_by_name($discordRoles);

            $settingsStmt = $pdo->prepare('SELECT * FROM guild_settings WHERE clan_id = :clan_id LIMIT 1');
            $settingsStmt->execute(['clan_id' => $clanId]);
            $guildSettings = $settingsStmt->fetch() ?: [];
            $rankMappings = bootstrap_existing_rank_mappings($pdo, $clanId);

            $createdRoleNames = [];

            foreach ($recommendedRoles as $definition) {
                $roleName = (string)$definition['name'];
                $matchedExistingRole = bootstrap_find_matching_role($rolesByName, $roleName);
                if ($matchedExistingRole !== null) {
                    $rolesByName[$roleName] = $matchedExistingRole;
                    continue;
                }

                $createdRole = discord_create_role($guildId, $roleName, [
                    'permissions' => $definition['permissions'],
                ]);

                $rolesByName[$roleName] = $createdRole;
                $createdRoleNames[] = $roleName;
            }

            $botUser = discord_get_bot_user();
            $hierarchyResult = bootstrap_reorder_admin_roles_beneath_bot($guildId, discord_get_guild_roles($guildId), (string)($botUser['id'] ?? ''));

            $discordRoles = discord_get_guild_roles($guildId);
            $rolesByName = bootstrap_role_index_by_name($discordRoles);

            $serverAdminRole = bootstrap_find_matching_role($rolesByName, 'Server Admin');
            $serverModeratorRole = bootstrap_find_matching_role($rolesByName, 'Server Moderator');
            $envAdminAssignments = ($serverAdminRole !== null)
                ? bootstrap_assign_server_admin_role_to_env_admins($guildId, (string)$serverAdminRole['id'], bootstrap_admin_user_ids_from_env())
                : [];

            $upsertGuildSettings = $pdo->prepare('INSERT INTO guild_settings (
                    clan_id,
                    discord_guild_id,
                    guild_name_cache,
                    server_admin_role_id,
                    server_admin_role_name_cache,
                    server_moderator_role_id,
                    server_moderator_role_name_cache
                ) VALUES (
                    :clan_id,
                    :discord_guild_id,
                    :guild_name_cache,
                    :server_admin_role_id,
                    :server_admin_role_name_cache,
                    :server_moderator_role_id,
                    :server_moderator_role_name_cache
                )
                ON DUPLICATE KEY UPDATE
                    discord_guild_id = VALUES(discord_guild_id),
                    guild_name_cache = VALUES(guild_name_cache),
                    server_admin_role_id = CASE
                        WHEN COALESCE(server_admin_role_id, "") = "" THEN VALUES(server_admin_role_id)
                        ELSE server_admin_role_id
                    END,
                    server_admin_role_name_cache = CASE
                        WHEN COALESCE(server_admin_role_id, "") = "" THEN VALUES(server_admin_role_name_cache)
                        ELSE server_admin_role_name_cache
                    END,
                    server_moderator_role_id = CASE
                        WHEN COALESCE(server_moderator_role_id, "") = "" THEN VALUES(server_moderator_role_id)
                        ELSE server_moderator_role_id
                    END,
                    server_moderator_role_name_cache = CASE
                        WHEN COALESCE(server_moderator_role_id, "") = "" THEN VALUES(server_moderator_role_name_cache)
                        ELSE server_moderator_role_name_cache
                    END');

            $upsertGuildSettings->execute([
                'clan_id' => $clanId,
                'discord_guild_id' => $guildId,
                'guild_name_cache' => (string)($guild['name'] ?? ''),
                'server_admin_role_id' => !empty($guildSettings['server_admin_role_id']) ? (string)$guildSettings['server_admin_role_id'] : (string)($serverAdminRole['id'] ?? ''),
                'server_admin_role_name_cache' => !empty($guildSettings['server_admin_role_id']) ? (string)($guildSettings['server_admin_role_name_cache'] ?? '') : (string)($serverAdminRole['name'] ?? ''),
                'server_moderator_role_id' => !empty($guildSettings['server_moderator_role_id']) ? (string)$guildSettings['server_moderator_role_id'] : (string)($serverModeratorRole['id'] ?? ''),
                'server_moderator_role_name_cache' => !empty($guildSettings['server_moderator_role_id']) ? (string)($guildSettings['server_moderator_role_name_cache'] ?? '') : (string)($serverModeratorRole['name'] ?? ''),
            ]);

            $insertMappingStmt = $pdo->prepare('INSERT INTO rs_rank_mappings (
                    clan_id,
                    rs_rank_name,
                    discord_role_id,
                    discord_role_name_cache,
                    is_enabled
                ) VALUES (
                    :clan_id,
                    :rs_rank_name,
                    :discord_role_id,
                    :discord_role_name_cache,
                    1
                )
                ON DUPLICATE KEY UPDATE
                    discord_role_name_cache = VALUES(discord_role_name_cache),
                    is_enabled = VALUES(is_enabled)');

            $mappingCreates = [];
            foreach (bootstrap_default_rank_targets() as $rankName => $targetRoleName) {
                $matchedRole = bootstrap_find_matching_role($rolesByName, $targetRoleName);
                if ($matchedRole === null) {
                    continue;
                }

                $existing = $rankMappings[$rankName] ?? ['role_ids' => []];
                $existingRoleIds = array_map('strval', $existing['role_ids'] ?? []);
                if ($existingRoleIds !== []) {
                    continue;
                }

                $insertMappingStmt->execute([
                    'clan_id' => $clanId,
                    'rs_rank_name' => $rankName,
                    'discord_role_id' => (string)$matchedRole['id'],
                    'discord_role_name_cache' => (string)$matchedRole['name'],
                ]);

                $mappingCreates[] = $rankName . ' → ' . (string)$matchedRole['name'];
            }

            $parts = [];
            $parts[] = $createdRoleNames === []
                ? 'No new roles were required.'
                : 'Created roles: ' . implode(', ', $createdRoleNames) . '.';

            $parts[] = 'Role order enforced: ' . ($hierarchyResult['server_admin_role_name'] ?: 'Server Admin') . ' and ' . ($hierarchyResult['server_moderator_role_name'] ?: 'Server Moderator') . ' were placed directly beneath bot role ' . ($hierarchyResult['bot_role_name'] ?: 'Bot') . '.';

            $autoFilledSettings = [];
            if (empty($guildSettings['server_admin_role_id']) && $serverAdminRole !== null) {
                $autoFilledSettings[] = 'Server Admin';
            }
            if (empty($guildSettings['server_moderator_role_id']) && $serverModeratorRole !== null) {
                $autoFilledSettings[] = 'Server Moderator';
            }
            $parts[] = $autoFilledSettings === []
                ? 'Server admin/mod settings were left unchanged.'
                : 'Auto-filled settings: ' . implode(', ', $autoFilledSettings) . '.';

            $parts[] = $mappingCreates === []
                ? 'No default rank mappings needed to be added.'
                : 'Added default rank mappings: ' . implode(', ', $mappingCreates) . '.';

            $parts[] = $envAdminAssignments === []
                ? 'No .env admin users needed the Server Admin role.'
                : 'Assigned Server Admin to configured .env admin user IDs present in the server: ' . implode(', ', $envAdminAssignments) . '.';

            $parts[] = 'Guest and Clan Member auto-fill is handled through rank mappings because this schema does not have dedicated guest/clan-member guild setting columns.';

            flash('success', implode(' ', $parts));
        } catch (Throwable $e) {
            flash('error', 'Role bootstrap failed: ' . $e->getMessage());
        }

        redirect('/admin/discord-role-bootstrap.php');
    }
}

require_once __DIR__ . '/../../app/views/header.php';
?>
<div class="card">
    <h2>Discord Role Bootstrap</h2>
    <p class="muted">Scans the current guild, matches recommended roles by exact name or simple plural variants, creates only missing recommended roles, keeps existing role permissions untouched, places Server Admin and Server Moderator directly beneath the bot role, and assigns Server Admin to any in-server users listed in ADMIN_DISCORD_USER_IDS.</p>
</div>

<?php if ($missingTables): ?>
    <div class="card">
        <span class="status bad">Setup Required</span>
        <p>Missing table(s): <?= h(implode(', ', $missingTables)) ?></p>
    </div>
<?php elseif ($scanError !== null): ?>
    <div class="card">
        <span class="status bad">Discord Error</span>
        <p><?= h($scanError) ?></p>
    </div>
<?php else: ?>
    <?php
        $missingCount = count($scanPlan['missing_role_names']);
        $settingFillCount = count(array_filter($scanPlan['settings'], static fn(array $row): bool => !empty($row['will_fill'])));
        $mappingFillCount = count(array_filter($scanPlan['mappings'], static fn(array $row): bool => !empty($row['will_fill'])));
    ?>
    <div class="grid two">
        <div class="card">
            <h3>Scan Summary</h3>
            <table>
                <tbody>
                    <tr><th>Guild</th><td><?= h((string)($guild['name'] ?? 'Unknown Guild')) ?></td></tr>
                    <tr><th>Recommended Roles</th><td><?= h((string)count($recommendedRoles)) ?></td></tr>
                    <tr><th>Already Present</th><td><?= h((string)(count($recommendedRoles) - $missingCount)) ?></td></tr>
                    <tr><th>Missing</th><td><?= $missingCount > 0 ? '<span class="status warn">' . h((string)$missingCount) . '</span>' : '<span class="status ok">0</span>' ?></td></tr>
                    <tr><th>Settings To Auto-Fill</th><td><?= $settingFillCount > 0 ? h((string)$settingFillCount) : '<span class="muted">0</span>' ?></td></tr>
                    <tr><th>Rank Mappings To Add</th><td><?= $mappingFillCount > 0 ? h((string)$mappingFillCount) : '<span class="muted">0</span>' ?></td></tr>
                </tbody>
            </table>
        </div>

        <div class="card">
            <h3>Deploy Behaviour</h3>
            <ul>
                <li>Creates only missing roles from the recommended list after checking exact and plural name matches.</li>
                <li>Applies permissions only when a role is newly created.</li>
                <li>Leaves existing role permissions untouched while moving Server Admin and Server Moderator directly beneath the bot role.</li>
                <li>Assigns the Server Admin role to any users listed in <code>ADMIN_DISCORD_USER_IDS</code> who are currently in the server.</li>
                <li>Auto-fills Server Admin / Server Moderator in guild settings only when those settings are currently blank.</li>
                <li>Adds default rank mappings only when a rank currently has no mapped Discord role.</li>
            </ul>
            <form method="post" style="margin-top:16px;">
                <input type="hidden" name="csrf_token" value="<?= h(post_csrf_token()) ?>">
                <input type="hidden" name="action" value="deploy_bootstrap">
                <button class="btn-primary" type="submit">Deploy Recommended Roles</button>
            </form>
        </div>
    </div>

    <div class="card">
        <h3>Recommended Roles</h3>
        <table>
            <thead>
                <tr>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Permission Profile</th>
                    <th>Notes</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($scanPlan['roles'] as $row): ?>
                    <?php $existing = $row['existing']; ?>
                    <tr>
                        <td>
                            <strong><?= h((string)$row['name']) ?></strong>
                            <?php if ($existing): ?>
                                <br><span class="small muted mono"><?= h((string)($existing['id'] ?? '')) ?></span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ($existing): ?>
                                <span class="status ok">Exists</span>
                            <?php else: ?>
                                <span class="status warn">Will Create</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php
                                $mode = (string)$row['permission_mode'];
                                echo $mode === 'administrator'
                                    ? 'Administrator'
                                    : ($mode === 'moderator' ? 'Message/User Moderation' : 'No automatic permissions');
                            ?>
                        </td>
                        <td><?= h((string)$row['description']) ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="grid two">
        <div class="card">
            <h3>Guild Settings Auto-Fill</h3>
            <table>
                <thead>
                    <tr>
                        <th>Setting</th>
                        <th>Current</th>
                        <th>Matched Role</th>
                        <th>Deploy Result</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($scanPlan['settings'] as $row): ?>
                        <tr>
                            <td><strong><?= h((string)$row['label']) ?></strong><br><span class="small muted"><?= h((string)$row['column']) ?></span></td>
                            <td>
                                <?php if ((string)$row['current_role_id'] !== ''): ?>
                                    <span class="status ok">Already Set</span><br>
                                    <span class="small muted mono"><?= h((string)$row['current_role_id']) ?></span>
                                <?php else: ?>
                                    <span class="muted">Blank</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if ($row['matched_role']): ?>
                                    <?= h((string)($row['matched_role']['name'] ?? '')) ?><br>
                                    <span class="small muted mono"><?= h((string)($row['matched_role']['id'] ?? '')) ?></span>
                                <?php else: ?>
                                    <span class="muted">No exact role match yet</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if (!empty($row['will_fill'])): ?>
                                    <span class="status warn">Will Auto-Fill</span>
                                <?php else: ?>
                                    <span class="muted">No change</span>
                                <?php endif; ?>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    <tr>
                        <td><strong>Clan Member</strong><br><span class="small muted">single-select mapping</span></td>
                        <td colspan="3" class="small muted">Handled through <code>rs_rank_mappings</code> because this schema has no dedicated <code>clan_member_role_id</code> column.</td>
                    </tr>
                    <tr>
                        <td><strong>Guest</strong><br><span class="small muted">single-select mapping</span></td>
                        <td colspan="3" class="small muted">Handled through <code>rs_rank_mappings</code> because this schema has no dedicated <code>guest_role_id</code> column.</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div class="card">
            <h3>Default Rank Mapping Bootstrap</h3>
            <table>
                <thead>
                    <tr>
                        <th>RS Rank</th>
                        <th>Target Discord Role</th>
                        <th>Current Mapping</th>
                        <th>Deploy Result</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($scanPlan['mappings'] as $row): ?>
                        <tr>
                            <td><strong><?= h((string)$row['rank_name']) ?></strong></td>
                            <td><?= h((string)$row['target_role_name']) ?></td>
                            <td>
                                <?php if (!empty($row['current_role_names'])): ?>
                                    <?= h(implode(', ', $row['current_role_names'])) ?>
                                <?php else: ?>
                                    <span class="muted">No mapped role</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if (!empty($row['will_fill'])): ?>
                                    <span class="status warn">Will Add</span>
                                <?php elseif ($row['matched_role']): ?>
                                    <span class="muted">No change</span>
                                <?php else: ?>
                                    <span class="muted">Target role missing</span>
                                <?php endif; ?>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    <tr>
                        <td><strong>Organiser</strong></td>
                        <td colspan="3" class="small muted">No recommended bootstrap mapping in P3.4.0 safe pass.</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
<?php endif; ?>

<?php require_once __DIR__ . '/../../app/views/footer.php'; ?>
