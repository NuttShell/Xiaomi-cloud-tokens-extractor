## Files for Building `token_extractor.exe` from `token_extractor.py` on Windows

**The folder contains two executable CMD files.**

`get_embedd_python.cmd` downloads a minimal **Embedded Python** distribution from the Python.org FTP server.

The Python version and architecture are specified in the `pyconfig.json` file.

If you need a specific Python build, simply specify the desired version and architecture in `pyconfig.json`.

The script will read the configuration and download that exact build.

If `pyconfig.json` is missing, or the specified Python version is not available on Python.org,

the script will switch to interactive mode and prompt you to choose the Python version and architecture.

Python will be downloaded and installed into the `\python` folder located next to the script.

The installed Embedded Python distribution is **not** registered in the system and does **not** affect any existing Python installations or other Python versions.

To install the required dependencies, edit the `requirements.txt` file. Its format is identical to the standard `requirements.txt` file,

with one exception: the first line must specify **PyInstaller**, since it is used to build the executable.

`make.cmd` builds an executable (`.exe`) from the Python source file.

For the build to succeed, the following files must be located in the same folder:

`icon.ico`

`token_extractor.spec`

**The compiled executable will be placed in the same folder as the script.**

For the build process to work correctly, the following three names must match:

In `make.cmd`:

`set "progname=token_extractor"`

and the following files:

`token_extractor.py`

`token_extractor.spec`

You may rename them as needed. For example:

In `make.cmd`:

`set "progname=My_token_extractor"`

and the corresponding files:

`My_token_extractor.py`
`My_token_extractor.spec`

## Russian:

## Файлы для самостоятельной сборки token_extractor.exe из token_extractor.py для Windows-платформ
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
