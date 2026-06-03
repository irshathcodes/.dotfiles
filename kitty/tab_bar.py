from kitty.tab_bar import draw_tab_with_powerline, draw_attributed_string, Formatter, as_rgb
from kitty.boss import get_boss
from kitty.fast_data_types import get_options
from kitty.utils import color_as_int


opts = get_options()
YELLOW_BG = as_rgb(color_as_int(opts.color11))
BLACK = as_rgb(color_as_int(opts.color0))
WHITE = as_rgb(color_as_int(opts.color7))


def draw_right_status(draw_data, screen, tab):
    # The tabs may have left some formats enabled. Disable them now.
    draw_attributed_string(Formatter.reset, screen)

    cells = create_cells(tab)

    while True:
        if not cells:
            return
        padding = screen.columns - screen.cursor.x - sum(len(text) + 2 for _, text in cells)
        if padding >= 0:
            break
        cells = cells[1:]

    if padding:
        screen.draw(" " * padding)

    tab_bg = as_rgb(int(draw_data.inactive_bg))

    for kind, cell in cells:
        if kind == "mode":
            screen.cursor.bg = YELLOW_BG
            screen.cursor.fg = BLACK
            screen.draw(f" {cell} ")
        else:
            screen.cursor.bg = tab_bg
            screen.cursor.fg = WHITE
            screen.draw(f"  {cell}")



def draw_tab(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data):
    end = draw_tab_with_powerline(draw_data, screen, tab, before, max_title_length, index, is_last, extra_data)

    if(is_last):
        draw_right_status(draw_data, screen, tab)

    return end


def create_cells(tab):
    cells = []
    mode = get_keyboard_mode()
    if mode:
        cells.append(("mode", mode))
    split_position = get_split_position()
    if split_position:
        cells.append(("status", split_position))
    session_name = get_session_name(tab)
    if session_name:
        cells.append(("status", session_name))
    return cells


def get_keyboard_mode():
    mode = get_boss().mappings.current_keyboard_mode_name
    return mode

def get_session_name(tab):
    return tab.session_name


def get_split_position():
    try:
        windows = get_boss().active_tab.windows
        total = windows.num_groups
        if total <= 1:
            return ""
        return f"W {windows.active_group_idx + 1}/{total}"
    except Exception:
        return ""
