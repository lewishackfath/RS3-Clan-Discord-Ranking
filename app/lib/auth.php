<?php
declare(strict_types=1);

function require_login(): void
{
    if (empty($_SESSION['admin_user'])) {
        redirect('/auth/login.php');
    }
}

function current_admin(): ?array
{
    return $_SESSION['admin_user'] ?? null;
}

function clear_admin_session(): void
{
    $_SESSION = [];
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_regenerate_id(true);
    }
}

function complete_admin_login(array $adminUser, string $accessToken): void
{
    session_regenerate_id(true);
    $_SESSION['admin_user'] = $adminUser;
    $_SESSION['oauth_access_token'] = $accessToken;
}

function admin_discord_user_is_allowlisted(?string $candidateUserId = null): bool
{
    $userId = trim((string)$candidateUserId);

    if ($userId === '') {
        $admin = current_admin();
        if (!$admin) {
            return false;
        }
        $userId = trim((string)($admin['id'] ?? ''));
    }

    if ($userId === '') {
        return false;
    }

    $allowedUsers = csv_ids((string)env('ADMIN_DISCORD_USER_IDS', ''));
    return $allowedUsers !== [] && in_array($userId, $allowedUsers, true);
}

function is_admin_authorised(?array $guildMember, array $guildRoles, ?string $candidateUserId = null): bool
{
    if (admin_discord_user_is_allowlisted($candidateUserId)) {
        return true;
    }

    if ($guildMember === null) {
        return false;
    }

    $allowedRoles = csv_ids((string)env('ADMIN_DISCORD_ROLE_IDS', ''));
    if ($allowedRoles) {
        foreach (($guildMember['roles'] ?? []) as $roleId) {
            if (in_array((string)$roleId, $allowedRoles, true)) {
                return true;
            }
        }
        return false;
    }

    return true;
}
