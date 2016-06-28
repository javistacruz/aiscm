#include <libguile.h>
#include <libavformat/avformat.h>


static scm_t_bits format_context_tag;

struct format_context_t {
  AVFormatContext *fmt_ctx;
  int video_stream_idx;
  AVCodecContext *video_dec_ctx;
};

SCM format_context_destroy(SCM scm_self)
{
  scm_assert_smob_type(format_context_tag, scm_self);
  struct format_context_t *self = (struct format_context_t *)SCM_SMOB_DATA(scm_self);
  if (self->video_dec_ctx) {
    avcodec_close(self->video_dec_ctx);
    self->video_dec_ctx = NULL;
  };
  if (self->fmt_ctx) {
    avformat_close_input(&self->fmt_ctx);
    self->fmt_ctx = NULL;
  };
  return SCM_UNSPECIFIED;
}

size_t free_format_context(SCM scm_self)
{
  struct format_context_t *self = (struct format_context_t *)SCM_SMOB_DATA(scm_self);
  format_context_destroy(scm_self);
  scm_gc_free(self, sizeof(struct format_context_t), "format-context");
  return 0;
}

SCM open_format_context(SCM scm_file_name, SCM scm_debug)
{
  SCM retval;
  struct format_context_t *self;
  const char *file_name = scm_to_locale_string(scm_file_name);
  self = (struct format_context_t *)scm_gc_calloc(sizeof(struct format_context_t), "format-context");
  self->video_stream_idx = -1;
  SCM_NEWSMOB(retval, format_context_tag, self);
  if (avformat_open_input(&self->fmt_ctx, file_name, NULL, NULL) < 0) {
    format_context_destroy(retval);
    scm_misc_error("open-format-context", "Error opening video file '~a'", scm_list_1(scm_file_name));
  };
  if (avformat_find_stream_info(self->fmt_ctx, NULL) < 0) {
    format_context_destroy(retval);
    scm_misc_error("open-format-context", "Could not find stream information for video file '~a'", scm_list_1(scm_file_name));
  };
  self->video_stream_idx = av_find_best_stream(self->fmt_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (self->video_stream_idx >= 0) {
    AVCodecContext *dec_ctx = self->fmt_ctx->streams[self->video_stream_idx]->codec;
    AVCodec *dec = avcodec_find_decoder(dec_ctx->codec_id);
    if (!dec) {
      format_context_destroy(retval);
      scm_misc_error("open-format-context", "Failed to find video codec for file '~a'", scm_list_1(scm_file_name));// TODO: print codec tag
    };
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "refcounted_frames", "1", 0);
    if (avcodec_open2(dec_ctx, dec, &opts) < 0) {
      format_context_destroy(retval);
      scm_misc_error("open-format-context", "Failed to open video codec for file '~a'", scm_list_1(scm_file_name));// TODO: print codec tag
    };
    self->video_dec_ctx = dec_ctx;
  };
  if (scm_is_true(scm_debug))
    av_dump_format(self->fmt_ctx, 0, file_name, 0);
  return retval;
}

SCM format_context_shape(SCM scm_self)
{
  scm_assert_smob_type(format_context_tag, scm_self);
  struct format_context_t *self = (struct format_context_t *)SCM_SMOB_DATA(scm_self);
  if (!self->video_dec_ctx)
    scm_misc_error("format-context-shape", "File format does not have a video stream", SCM_EOL);
  int width = self->video_dec_ctx->width;
  int height = self->video_dec_ctx->height;
  return scm_list_2(scm_from_int(width), scm_from_int(height));
}

SCM format_context_read_video(SCM scm_self)
{
  scm_assert_smob_type(format_context_tag, scm_self);
  struct format_context_t *self = (struct format_context_t *)SCM_SMOB_DATA(scm_self);
  return scm_self;
}

void init_ffmpeg(void)
{
  format_context_tag = scm_make_smob_type("format-context", sizeof(struct format_context_t));
  scm_set_smob_free(format_context_tag, free_format_context);
  av_register_all();
  scm_c_define_gsubr("open-format-context", 2, 0, 0, open_format_context);
  scm_c_define_gsubr("format-context-shape", 1, 0, 0, format_context_shape);
  scm_c_define_gsubr("format-context-read-video", 1, 0, 0, format_context_read_video);
}
