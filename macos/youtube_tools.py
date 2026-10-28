"""Use the app's maintained downloader instead of an unrelated Homebrew install."""
import os
import pathlib
import shutil

RUNTIME=pathlib.Path.home()/'Library/Application Support/English Routine/download-runtime'

def downloader_path():
    if os.environ.get('ENGLISH_YTDLP'):
        return os.environ['ENGLISH_YTDLP']
    bundled=RUNTIME/'bin/yt-dlp'
    return str(bundled) if bundled.is_file() else '/opt/homebrew/bin/yt-dlp'

def command(executable):
    args=[executable,'--ignore-config','--no-playlist']
    # Finder-launched apps do not inherit the interactive shell's runtime setup.
    deno=shutil.which('deno')
    if not deno and pathlib.Path('/opt/homebrew/bin/deno').is_file():
        deno='/opt/homebrew/bin/deno'
    if deno:
        args.extend(['--js-runtimes','deno:'+deno])
    return args
