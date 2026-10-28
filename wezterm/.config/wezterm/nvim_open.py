"""Discover existing Neovim servers and open terminal file references over RPC."""

import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import sys
from urllib.parse import unquote, urlsplit


def remote(server, code, data=None):
    # Vim single-quoted strings escape quotes by doubling them; no shell involved.
    def literal(value):
        return "'" + value.replace("'", "''") + "'"

    expression = "luaeval({}, {})".format(
        literal("(function() " + code + " end)()"), literal(json.dumps(data))
    )
    nvim = shutil.which("nvim") or "/opt/homebrew/bin/nvim"
    result = subprocess.run(
        [nvim, "--server", server, "--remote-expr", expression],
        capture_output=True, text=True, timeout=3, check=True,
    )
    return json.loads(result.stdout)


def instances():
    result = subprocess.run(
        ["/usr/sbin/lsof", "-a", "-u", str(os.getuid()), "-c", "nvim", "-U", "-Fpn"],
        capture_output=True, text=True, timeout=5,
    )
    servers = []
    seen = set()
    for entry in result.stdout.splitlines():
        if not entry.startswith("n/"):
            continue
        server = entry[1:]
        if server in seen or Path(server).name.startswith("fzf"):
            continue
        seen.add(server)
        try:
            if not stat.S_ISSOCK(os.stat(server).st_mode):
                continue
            info = remote(server, "return vim.json.encode({cwd=vim.fn.getcwd(), "
                          "pane=vim.env.WEZTERM_PANE, pid=vim.fn.getpid()})")
            if info.get("pane"):
                info["server"] = server
                servers.append(info)
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
    return sorted(servers, key=lambda item: (item["cwd"], item["pid"]))


def reference(text):
    text = text.strip()
    if text.startswith("nvim-path:"):
        text = text[len("nvim-path:"):]
    if text.startswith("file://"):
        url = urlsplit(text)
        if url.hostname not in (None, "", "localhost", socket.gethostname()):
            raise ValueError("Only local file links can be opened in local Neovim")
        text = unquote(url.path) + ("#" + url.fragment if url.fragment else "")
    match = re.search(r"(?:#L(\d+)(?:-L?\d+)?|:(\d+)(?::(\d+))?|\|(\d+)(?:\s+col\s+(\d+)(?:-\d+)?)?\|?)$", text)
    line = column = 1
    if match:
        line = int(match[1] or match[2] or match[4])
        column = int(match[3] or match[5] or 1)
        text = text[:match.start()]
    return Path(text).expanduser(), max(line, 1), max(column, 1)


def resolve_path(path, source_cwd, editor_cwd):
    if not path.is_absolute():
        source = Path(source_cwd)
        editor = Path(editor_cwd)
        # Terminal apps can maintain a workspace independently of their process
        # cwd. A workspace-relative reference may start above Neovim's project.
        roots = dict.fromkeys([source, editor, *editor.parents, *source.parents])
        candidates = [root / path for root in roots]
        path = next((candidate for candidate in candidates if candidate.is_file()), candidates[0])
    path = path.resolve()
    if not path.is_file():
        raise ValueError(f"File not found: {path}")
    return path


def open_file(server, text, source_cwd):
    path, line, column = reference(text)
    info = remote(server, "return vim.json.encode({cwd=vim.fn.getcwd()})")
    path = resolve_path(path, source_cwd, info["cwd"])
    return remote(server, """
        local data = vim.json.decode(_A)
        if vim.api.nvim_win_get_config(0).relative ~= '' then
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.api.nvim_win_get_config(win).relative == '' then
                    vim.api.nvim_set_current_win(win)
                    break
                end
            end
        end
        vim.cmd('drop ' .. vim.fn.fnameescape(data.path))
        local row = math.min(data.line, vim.api.nvim_buf_line_count(0))
        local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
        vim.api.nvim_win_set_cursor(0, {row, math.min(data.column - 1, #text)})
        vim.cmd('normal! zvzz')
        return vim.json.encode({ok=true})
    """, {"path": str(path), "line": line, "column": column})


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["list"]:
            print(json.dumps(instances()))
        elif len(sys.argv) == 5 and sys.argv[1] == "open":
            print(json.dumps(open_file(*sys.argv[2:])))
        else:
            raise ValueError("Usage: nvim_open.py list | open SERVER PATH SOURCE_CWD")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(getattr(error, "stderr", None) or str(error), file=sys.stderr)
        sys.exit(1)
