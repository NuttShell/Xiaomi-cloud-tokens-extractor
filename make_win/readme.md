## Files for building token_extractor.exe from token_extractor.py yourself, for Windows

Download and unpack archive:
[win_build.zip](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/win_build.zip)

**The folder contains two executable cmd files.**

`get_embedd_python.cmd` — lets you download a minimal Embedded Python build from the python.org ftp server;

the version and architecture are set in the `pyconfig.json` file.

If you need a specific build, specify its version and architecture in `pyconfig.json`, and the script will read it

and download exactly that build.

If `pyconfig.json` is missing, or the version it specifies isn't available on python.org, the script will offer an

interactive choice of Python version and architecture.

Python will be downloaded and installed into a `\python` folder next to the script.

The installed Python is not registered anywhere in the system and does not affect any other Python versions already

installed on the machine.

To install the required dependencies, edit the `requirements.txt` file; its structure and format are the same as a standard

`requirements.txt`, except that the first line must be PyInstaller, since the whole point is to build an exe file with it.

`make.cmd` — lets you build an exe file from the .py source.

For the build to work correctly, the following files must be present alongside it:

`icon.ico`

`token_extractor.spec`

**The compiled exe will be placed in the folder next to the script.**

For the build to work correctly, three names must match:

the line in `make.cmd`:

`set "progname=token_extractor"`,

and the file names in the folder:

`token_extractor.py`

`token_extractor.spec`

You can rename all of these to whatever you like, for example:

the line in `make.cmd`:

`set "progname=My_token_extractor"`

and the file names in the folder:

`My_token_extractor.py`
`My_token_extractor.spec`

## Russian:

## Файлы для самостоятельной сборки token_extractor.exe из token_extractor.py для Windows-платформ

Скопируйте token_extractor.py в папку с скриптами

**В папке два исполняемых cmd файла.**

`get_embedd_python.cmd` - позволяет скачать минимальную сборку Embedded Python с ftp python.org,
версия и архитектура прописаны в файле `pyconfig.json`
Если вам необходимо скачать определенную сборку, пропишите ее версию и архитектуру в файле `pyconfig.json`,
скрипт прочитает и скачает именно ее.
Если `pyconfig.json` отсутствует, или указанной в нем версии нет на python.org,
скрипт в интерактивном режиме предложит выбрать версию python и архитектуру.
Python будет скачан и установлен в папку \python рядом со скриптом. 

Установленный Python не прописывается в системе и никак
не влияет на уже установленные копии python других версий.

Для установки необходимых зависимостей отредактируйте файл `requirements.txt`, по строению и формату он аналогичен стандартному
`requirements.txt`, за тем исключением, что первой строкой должен быть прописан PyInstaller, так как подразумевается сборка exe файла
с его помощью.

`make.cmd` - позволяет собрать exe файл из .py исходника.
Для корректной сборки рядом должны находится файлы:
`icon.ico`
`token_extractor.spec`

**Скомпилированный exe будет помещен в папку рядом со скриптом.**

Для корректной сборки exe должны совпадать три имени:
в файле `make.cmd` строка:

`set "progname=token_extractor"`,

и имена файлов в папке:
`token_extractor.py`
`token_extractor.spec`

которые вы можете поменять на свои, например:

в файле `make.cmd` строка:

`set "progname=My_token_extractor"`

и имена файлов в папке:
`My_token_extractor.py`
`My_token_extractor.spec`
