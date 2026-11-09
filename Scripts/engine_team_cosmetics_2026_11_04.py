"""Team, Assist cosmetics and portable Vulkan null-handle parity; immutable pins untouched."""
from pathlib import Path
PAIRS = {'app/src/game/redraw.c': [('          // The tag hangs off the head, over everything else the snake is\n'
                            '          // wearing, which is where the mod puts it too.\n'
                            '          const int hide_own_cosmetics =\n'
                            '              usrs->hotkeys[HOTKEY_ASSIST].active &&\n'
                            '              usrs->ext.assist_hide_cosmetics &&\n'
                            '              o->id == gdata->data.snake_id;\n'
                            '          if (!hide_own_cosmetics)\n'
                            '          tags_draw(env, o, o->id == gdata->data.snake_id, false);\n'
                            '\n'
                            '          // accessory:\n'
                            '          if (!hide_own_cosmetics && mode->show_accessories && o->accessory < '
                            'NUM_ACCESSORIES) {\n'
                            '            accessory_data* acc = gdata->accessories + o->accessory;\n'
                            '            ex = acc->of * cosf(fang) * ed;\n',
                            '          // The tag hangs off the head, over everything else the snake is\n'
                            '          // wearing, which is where the mod puts it too.\n'
                            '          const int hide_cosmetics =\n'
                            '              usrs->hotkeys[HOTKEY_ASSIST].active &&\n'
                            '              usrs->ext.assist_hide_cosmetics;\n'
                            '          if (!hide_cosmetics)\n'
                            '          tags_draw(env, o, o->id == gdata->data.snake_id, false);\n'
                            '\n'
                            '          // accessory:\n'
                            '          if (!hide_cosmetics && mode->show_accessories && o->accessory < '
                            'NUM_ACCESSORIES) {\n'
                            '            accessory_data* acc = gdata->accessories + o->accessory;\n'
                            '            ex = acc->of * cosf(fang) * ed;\n'),
                           ("          // Wyrm's own hair, ears and glasses: the player's snake only, and\n"
                            '          // only on this phone (platform/android_look.c).\n'
                            '          if (!hide_own_cosmetics && o->id == gdata->data.snake_id)\n'
                            '            wyrm_look_draw(env, hx, hy, fang, lsz, ea, mww2, mhh2);\n'
                            '#endif\n',
                            "          // Wyrm's own hair, ears and glasses: the player's snake only, and\n"
                            '          // only on this phone (platform/android_look.c).\n'
                            '          if (!hide_cosmetics && o->id == gdata->data.snake_id)\n'
                            '            wyrm_look_draw(env, hx, hy, fang, lsz, ea, mww2, mhh2);\n'
                            '#endif\n')],
 'app/src/imgui_setup.c': [('      .PipelineCache = NULL,', '      .PipelineCache = VK_NULL_HANDLE,'),
                           ('  igImplVulkan_RenderDrawData(igGetDrawData(), cmd, NULL);',
                            '  igImplVulkan_RenderDrawData(igGetDrawData(), cmd, VK_NULL_HANDLE);')],
 'app/src/platform/android_settings.c': [('     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(ext.snake_shadow[1])},\n'
                                          '    {"assist.hide_cosmetics", "assist", "Hide own tag and '
                                          'accessories",\n'
                                          '     "While assist is on, your tag, accessory and Wyrm look are '
                                          'hidden.",\n'
                                          '     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(ext.assist_hide_cosmetics)},\n',
                                          '     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(ext.snake_shadow[1])},\n'
                                          '    {"assist.hide_cosmetics", "assist", "Hide all tags and '
                                          'accessories",\n'
                                          '     "While assist is on, all tags, accessories, hair and Wyrm '
                                          'look decorations are hidden.",\n'
                                          '     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(ext.assist_hide_cosmetics)},\n')],
 'app/src/platform/android_team.c': [('    return;\n'
                                      '  presence_published_at = now;\n'
                                      '  presence_was_playing = playing;\n'
                                      '\n'
                                      '  int x = 0;\n',
                                      '    return;\n  presence_published_at = now;\n\n  int x = 0;\n'),
                                     ('  int sid = 0;\n'
                                      '  if (playing) {\n'
                                      '    int length = tdarray_length(game->data.snakes);\n'
                                      '    if (length > 0) {\n'
                                      '      snake* me = game->data.snakes + (length - 1);\n'
                                      '      if (game->data.snake_id == me->id) {\n'
                                      '        x = (int)(me->xx + me->fx);\n'
                                      '        y = (int)(me->yy + me->fy);\n',
                                      '  int sid = 0;\n'
                                      '  if (playing) {\n'
                                      '    int length = game->data.snakes ? '
                                      'tdarray_length(game->data.snakes) : 0;\n'
                                      '    bool found = false;\n'
                                      '    if (length > 0) {\n'
                                      '      /* Other snakes can arrive after ours; array order is not '
                                      'identity. */\n'
                                      '      snake* me = NULL;\n'
                                      '      for (int i = 0; i < length; ++i) {\n'
                                      '        if (game->data.snakes[i].id == game->data.snake_id) {\n'
                                      '          me = game->data.snakes + i;\n'
                                      '          break;\n'
                                      '        }\n'
                                      '      }\n'
                                      '      if (me) {\n'
                                      '        found = true;\n'
                                      '        x = (int)(me->xx + me->fx);\n'
                                      '        y = (int)(me->yy + me->fy);\n'),
                                     ('      }\n    }\n  }\n\n  /*\n',
                                      '      }\n'
                                      '    }\n'
                                      '    /* Joining/respawn may expose PLAYING before our snake arrives. '
                                      'Never\n'
                                      '       publish a fabricated in-arena 0,0; publish again as soon as it '
                                      'exists. */\n'
                                      '    if (!found) playing = false;\n'
                                      '  }\n'
                                      '  presence_was_playing = playing;\n'
                                      '\n'
                                      '  /*\n')],
 'app/src/rendering/bd_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                      'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                      1)],
 'app/src/rendering/bg_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                      'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                      1)],
 'app/src/rendering/bp_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                      'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                      1)],
 'app/src/rendering/bst_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                       'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                       1)],
 'app/src/rendering/fd_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                      'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                      3)],
 'app/src/rendering/mm_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                      'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                      1)],
 'app/src/rendering/spr_renderer.c': [('vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,',
                                       'vkCreateGraphicsPipelines(\n      ctx->device, VK_NULL_HANDLE, 1,',
                                       1)]}

def apply(root):
    for relative, pairs in PAIRS.items():
        p = Path(root) / relative
        s = p.read_text(encoding="utf-8")
        for pair in pairs:
            old, new = pair[:2]
            count = pair[2] if len(pair) == 3 else 1
            if relative == "app/src/game/redraw.c":
                if "Wyrm's own hair" in old:
                    old = "if (!hide_own_cosmetics && o->id == gdata->data.snake_id)"
                    new = "if (!hide_cosmetics && o->id == gdata->data.snake_id)"
            assert s.count(old) == count, (relative, "team/cosmetic anchor")
            s = s.replace(old, new, count)
        p.write_text(s, encoding="utf-8")
