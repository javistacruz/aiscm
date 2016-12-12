# Input/output
## Loading/saving images using ImageMagick

An image can be read from disk using *read-image* which uses the ImageMagick library to load the image.

![fubk.png](fubk.png "Test input image")

```Scheme
@../tests/integration/read_image.scm@
```

Analogous *write-image* writes an image to disk.

```Scheme
@../tests/integration/write_image.scm@
```

![scaled-pattern.png](scaled-pattern.png "Output image")

## Xorg display
### Images

As shown above, you can display images using the method *show* as follows:

```Scheme
@../tests/integration/read_image.scm@
```

One can also display a list of images:

![fubk-colours.png](fubk-colours.png "List of images")

```Scheme
@../tests/integration/xorg_image_list.scm@
```

### Videos

It is also possible to display a video using the *show* method:

```Scheme
@../tests/integration/xorg_video.scm@
```

A function returning lists of images can be used to display multiple videos synchronously.

```Scheme
@../tests/integration/xorg_video_list.scm@
```

If necessary, one can also handle the display and window objects directly.
Possible types of output are *IO-XIMAGE*, *IO-OPENGL*, and *IO-XVIDEO*.

```Scheme
@../tests/integration/xorg_window.scm@
```

## Video for Linux version 2 (V4L2)

![v4l2.jpg](v4l2.jpg "V4L2 input image")

As shown above already, you can open a camera and grab a frame as follows.

```Scheme
@../tests/integration/grab.scm@
```

It is also possible to specify the device, a channel, and a closure for selecting the video mode.

```Scheme
@../tests/integration/camera_mode.scm@
```

## Pulse audio

The following example program creates a sine wave and outputs it to the audio device.

```Scheme
@../tests/integration/pulse_out.scm@
```

The *drain* method waits for the content of the audio buffer to finish playing.
The method *flush* (not shown here) can be used to empty the audio buffer.

Audio data can be recorded in a similar fashion.
The following example records 3 seconds of audio data and then plays it back.

```Scheme
@../tests/integration/pulse_in.scm@
```

## Video files

<div class="figure">
<video src="av-sync.mp4" controls></video>
</div>

The following example shows how to use the FFmpeg interface to open and view a video.
The video presentation time stamps are used to display the video at the correct speed.
The method *latency* is used to determine the delay of the audio buffer.

```Scheme
@../tests/integration/ffvideo.scm@
```

The method *pts=* can be used to seek to an absolute position in audio/video streams:

```Scheme
@../tests/integration/pts.scm@
```

Note that *FFmpeg* also supports network streaming of video data.
I.e. the following example will play the [Sintel short film](https://durian.blender.org/) from a web server.

<div class="figure">
<a href="http://peach.themazzone.com/durian/movies/sintel-1024-surround.mp4"><img src="sintel.jpg" title="Sintel short movie" /></a>
</div>

```Scheme
@../tests/integration/ffstream.scm@
```

## Audio files

One can play samples from an audio file by passing them to the audio device using the *write-audio* method.
It is also possible to pass a function returning consecutive audio samples as shown below.

<div class="figure">
<audio src="test.mp3" controls></audio>
</div>

```Scheme
@../tests/integration/ffaudio.scm@
```
