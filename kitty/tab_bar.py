from kitty.tab_bar import (draw_tab_with_powerline, draw_attributed_string, Formatter
,as_rgb,
)
from kitty.boss import get_boss
from kitty.fast_data_types import get_options
from kitty.utils import color_as_int



opts = get_options()
YELLOW_BG =  as_rgb(color_as_int(opts.color11))
BLACK =  as_rgb(color_as_int(opts.color0))
WHITE =  as_rgb(color_as_int(opts.color7))

def draw_right_status(draw_data, screen, tab):
    # The tabs may have left some formats enabled. Disable them now.
    draw_attributed_string(Formatter.reset, screen)

    cells = create_cells(tab)

    while True:
        if not cells:
            return
        padding = screen.columns - screen.cursor.x - sum(len(c) + 3 for c in cells)
        if padding >= 0:
            break
        cells = cells[1:]

    if padding:
        screen.draw(" " * padding)

    tab_bg = as_rgb(int(draw_data.inactive_bg))
    tab_fg = as_rgb(int(draw_data.inactive_fg))
    default_bg = as_rgb(int(draw_data.default_bg))

    for i, cell in enumerate(cells):
        if(cell and i == 0): 
            screen.cursor.bg = YELLOW_BG
            screen.cursor.fg = BLACK
            screen.draw(f" {cell} ")
        else:
            screen.cursor.bg = tab_bg
            screen.cursor.fg = WHITE
            screen.draw(f"  {cell}")



def draw_tab(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data):
    draw_tab_with_powerline(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data)

    if(is_last):
        draw_right_status(draw_data, screen, tab)


def create_cells(tab):
    return [get_keyboard_mode(), get_session_name(tab)]


def get_keyboard_mode():
    mode = get_boss().mappings.current_keyboard_mode_name
    return mode

def get_session_name(tab):
    return tab.session_name

