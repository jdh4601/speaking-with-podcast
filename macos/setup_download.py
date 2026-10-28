"""Install/update only English Routine's YouTube downloader dependencies."""
import pathlib
import subprocess
import venv
from youtube_tools import RUNTIME

venv.EnvBuilder(with_pip=True).create(RUNTIME)
subprocess.run([str(RUNTIME/'bin/python'),'-m','pip','install','--upgrade','-r',str(pathlib.Path(__file__).with_name('requirements-download.txt'))],check=True)
print('YouTube downloader ready:',RUNTIME/'bin/yt-dlp')
