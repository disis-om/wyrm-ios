"""Coalesce duplicate SDL resize events without suppressing explicit recovery."""
from pathlib import Path
PAIRS = {'thermite/src/framework/twindow.c': [('      window->size[0] = width;\n'
                                       '      window->size[1] = height;\n'
                                       '      window->_refresh = true;',
                                       '      bool changed = window->size[0] != width || '
                                       'window->size[1] != height;\n'
                                       '      window->size[0] = width;\n'
                                       '      window->size[1] = height;\n'
                                       '      /* SDL may echo a resize for the swapchain we just '
                                       'recreated. A\n'
                                       '         duplicate size must not trigger another healthy '
                                       'swapchain rebuild.\n'
                                       '         Explicit refresh requests and lost-surface '
                                       'recovery remain pending. */\n'
                                       '      if (changed || (env->ctx &&\n'
                                       '          (env->ctx->surface_lost || '
                                       '!env->ctx->swapchain_ok)))\n'
                                       '        window->_refresh = true;')]}
def apply(root):
    for relative,pairs in PAIRS.items():
        p=Path(root)/relative;s=p.read_text(encoding='utf-8')
        for old,new in pairs:
            assert s.count(old)==1,(relative,'resize event anchor')
            s=s.replace(old,new,1)
        p.write_text(s,encoding='utf-8')
