# Video Compressor Script

A smart Bash script to **compress and downscale videos** (local files or YouTube URLs) to a target file size, with automatic bitrate and resolution selection, hardware acceleration, and optional cleanup.

## Features

- **Input:** Local video files or YouTube (or similar) URLs
- **Target file size:** Specify desired output size in MB
- **Automatic bitrate & resolution:** Chooses best quality for your size
- **Manual override:** Force a specific resolution (360p, 480p, 720p, 1080p)
- **Hardware acceleration:** Uses NVIDIA, Intel, AMD, or Apple encoders if available
- **Smart cleanup:** Optionally deletes temporary downloads
- **Cross-platform:** Works on Linux, macOS, and Windows (with Bash)

---

## Requirements

- `ffmpeg`
- `ffprobe`
- `yt-dlp`
- `jq`
- `bc`

The script checks for these and gives install hints if missing.

---

## Usage

```bash
./mp4.sh -i <input> [options]
```


Or, to run from anywhere, **add the script to your `PATH`**:



#### 1. Make the script executable:

```bash
chmod +x mp4.sh
```



#### 2. Move it to a directory in your `PATH` (e.g., `/usr/local/bin` or `~/bin`):

```bash
mv mp4.sh /usr/local/bin/mp4.sh
```

**Or**, if you want to use it without the `.sh` extension:

```bash
mv mp4.sh /usr/local/bin/mp4
```



#### 3. Now you can run it from anywhere:

```bash
mp4.sh -i <input> [options]
```

or

```bash
mp4 -i <input> [options]
```



> 💡 **Tip:** If you use `~/bin` and it’s not in your `PATH`, add this to your `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/bin:$PATH"
```





### Arguments

| Option                | Description                                                      |
|-----------------------|------------------------------------------------------------------|
| `-i`, `--input`       | **(Required)** Input file path or URL                            |
| `-s`, `--target-size` | Target output size in MB (default: 1000)                         |
| `-r`, `--resolution`  | Force resolution: 360p, 480p, 720p, 1080p (auto if not set)      |
| `-c`, `--cleanup`     | Auto-delete temp download (no prompt, only for URL input)        |

### Examples

#### Compress a local file to 500 MB, auto quality

```bash
./video-compress.sh -i mymovie.mp4 -s 500
```

#### Download and compress a YouTube video to 300 MB, force 720p

```bash
./video-compress.sh -i "https://youtu.be/xyz" -s 300 -r 720p
```

#### Download, compress, and auto-delete temp file

```bash
./video-compress.sh -i "https://youtu.be/xyz" -s 200 -c
```

---

## How it Works

1. **Checks dependencies** and suggests install commands if missing.
2. **Parses arguments** and fetches video metadata (duration, title, etc.).
3. **Calculates optimal bitrate** for your target size.
4. **Selects best resolution** for quality/size, unless overridden.
5. **Downloads** the video (if URL) at the chosen resolution.
6. **Probes video dimensions and bitrate** to avoid upscaling or increasing file size.
7. **Downscales** if needed.
8. **Compresses** using `ffmpeg`, with hardware acceleration if available.
9. **Cleans up** temp files if requested.

---

## Output

- Output file is named:  
  `
  <basename>_<resolution>_<targetsize>M.mp4
  `
  Example: `MyVideo_720p_300M.mp4`

---

## Notes

- **Hardware acceleration**: The script auto-detects and uses the best available encoder (NVIDIA, Intel, AMD, Apple VideoToolbox). Falls back to software if none found.
- **No upscaling**: If the source video is lower quality than your target, it won’t upscale or increase bitrate.
- **Audio**: Encoded to AAC at 128 kbps.

---

## Troubleshooting

- If you see "Missing dependencies", follow the install hints for your OS.
- If `yt-dlp` fails, check your network or update `yt-dlp`.
- For hardware encoding, ensure your drivers and `ffmpeg` build support your hardware.

---

## License

MIT License (or specify your own)

---

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)
- [jq](https://stedolan.github.io/jq/)
- [bc](https://www.gnu.org/software/bc/)

---

**Happy compressing!** 🚀

