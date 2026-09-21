from pathlib import Path

root = Path(__file__).resolve().parent.parent
swift = (root / "SourcesShell" / "WyrmTeam.swift").read_text()
ui = (root / "SourcesShell" / "WyrmDesignDetails.swift").read_text()
team_c = (root / "SharedEngine" / "app" / "src" / "platform" / "android_team.c").read_text()
tags_c = (root / "SharedEngine" / "app" / "src" / "game" / "tags.c").read_text()
snake_h = (root / "SharedEngine" / "app" / "src" / "game" / "snake.h").read_text()
callback_c = (root / "SharedEngine" / "app" / "src" / "network" / "callback.c").read_text()
ntl_net_c = (root / "SharedEngine" / "app" / "src" / "network" / "ntl_net.c").read_text()
overlay_c = (root / "SharedEngine" / "app" / "src" / "game" / "ui_overlay.c").read_text()

for field in ("auth", "tid", "nick", "score", "valx", "valy", "bot", "sos",
              "food", "srv", "sid", "msg", "rank", "tg", "ver"):
    assert f'URLQueryItem(name: "{field}"' in swift, field
assert "4_000_000_000" in swift
assert "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in swift
assert "WyrmDiagnostics.record(\"NTL Team poll accepted members=" in swift
for line in swift.splitlines():
    if "WyrmDiagnostics.record" in line:
        assert "credentials.auth" not in line and "credentials.teamID" not in line

assert "snake_find_by_ntl_id(game->data.snakes, snake_count" in team_c
assert "tags_set(target->id, tags_from_ntl_id(member->tag))" in team_c
assert "WyrmIOSTeamPresenceSnapshot" in team_c
assert "WyrmIOSSetTeamMembers" in team_c
assert "%63[^\\t]\\t%d\\t%d\\t%d\\t%d\\t%d\\t%d\\t%d\\t%d" in team_c

assert "int ntl_id;" in snake_h
assert "session_id & 63u" in snake_h
assert "arena_id & 1023u" in snake_h
assert "current->ntl_id = ntl_id" in callback_c
assert "o.ntl_id = id" in callback_c
assert "snake_find_by_ntl_id(gdata->data.snakes, count, ntl_id)" in ntl_net_c
assert "sid = me->ntl_id" in ntl_net_c
assert overlay_c.index("android_team_begin_frame();") < overlay_c.index("if (usrs->hotkeys[HOTKEY_HUD].active)")

assert "#define ROPE_POINTS 10" in tags_c
assert "#define ROPE_STEP (1.0f / 60.0f)" in tags_c
assert "#define ROPE_MAX_STEPS 4" in tags_c
for literal in ("3.3332f", "0.08333f", "0.838f", "0.248f", "5.0f", "4.0f", "3.0f", "2.0f"):
    assert literal in tags_c, literal

assert "remaining engine boundary" not in ui
assert "@AppStorage(\"wyrm.ios.team.id\")" not in ui
assert "NTL 9.68 compatible" in ui
print("NTL Team/rope contracts verified")
