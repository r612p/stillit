video downloader with gui
just open the file, copy and paste video and select
the format you want


credit to ffmpeg and ytdlp - their packages are 
in this workspace and are used to do the downloading

## building it yourself (windows)

you need:
- a JDK 25 or newer (it has to include `jpackage`, which every full JDK does)
- the JavaFX SDK for windows x64, from https://gluonhq.com/products/javafx/ -
  unzip it into a `lib\` folder in this repo (or leave it unzipped in Downloads)
- `yt-dlp.exe` in your user folder or on PATH
- ffmpeg (`winget install Gyan.FFmpeg`)

then run, from this folder:

```
powershell -ExecutionPolicy Bypass -File build.ps1
powershell -ExecutionPolicy Bypass -File install.ps1
```

`build.ps1` finds everything above on its own. to use a specific copy, pass
`-Jdk`, `-Fx`, `-YtDlp` or `-Ffmpeg` with its path.
