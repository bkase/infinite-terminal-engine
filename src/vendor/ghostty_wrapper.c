#include "ite_ghostty_wrapper.h"

#include <ghostty/vt.h>

static GhosttyOptionAsAlt map_option_as_alt(ite_ghostty_option_as_alt_e option_as_alt) {
  switch (option_as_alt) {
    case ITE_GHOSTTY_OPTION_AS_ALT_FALSE:
      return GHOSTTY_OPTION_AS_ALT_FALSE;
    case ITE_GHOSTTY_OPTION_AS_ALT_TRUE:
      return GHOSTTY_OPTION_AS_ALT_TRUE;
    case ITE_GHOSTTY_OPTION_AS_ALT_LEFT:
      return GHOSTTY_OPTION_AS_ALT_LEFT;
    case ITE_GHOSTTY_OPTION_AS_ALT_RIGHT:
      return GHOSTTY_OPTION_AS_ALT_RIGHT;
  }

  return GHOSTTY_OPTION_AS_ALT_FALSE;
}

static GhosttyKeyAction map_action(uint8_t action) {
  switch (action) {
    case ITE_GHOSTTY_KEY_ACTION_RELEASE:
      return GHOSTTY_KEY_ACTION_RELEASE;
    case ITE_GHOSTTY_KEY_ACTION_PRESS:
      return GHOSTTY_KEY_ACTION_PRESS;
    case ITE_GHOSTTY_KEY_ACTION_REPEAT:
      return GHOSTTY_KEY_ACTION_REPEAT;
  }

  return GHOSTTY_KEY_ACTION_PRESS;
}

const char *ite_ghostty_vendor_snapshot(void) {
  return "332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28";
}

uint16_t ite_ghostty_key_code_a(void) {
  return (uint16_t)GHOSTTY_KEY_A;
}

uint16_t ite_ghostty_key_code_enter(void) {
  return (uint16_t)GHOSTTY_KEY_ENTER;
}

bool ite_ghostty_paste_is_safe(const char *data, size_t len) {
  return ghostty_paste_is_safe(data, len);
}

ite_ghostty_result_e ite_ghostty_encode_key(
    const ite_ghostty_key_event_s *event,
    ite_ghostty_option_as_alt_e option_as_alt,
    char *out_buf,
    size_t out_buf_size,
    size_t *out_len) {
  if (event == NULL) return ITE_GHOSTTY_RESULT_INVALID_VALUE;

  GhosttyKeyEncoder encoder = NULL;
  GhosttyKeyEvent ghostty_event = NULL;

  const GhosttyResult new_encoder_result = ghostty_key_encoder_new(NULL, &encoder);
  if (new_encoder_result != GHOSTTY_SUCCESS) return (ite_ghostty_result_e)new_encoder_result;

  const GhosttyResult new_event_result = ghostty_key_event_new(NULL, &ghostty_event);
  if (new_event_result != GHOSTTY_SUCCESS) {
    ghostty_key_encoder_free(encoder);
    return (ite_ghostty_result_e)new_event_result;
  }

  const GhosttyOptionAsAlt option = map_option_as_alt(option_as_alt);
  ghostty_key_encoder_setopt(
      encoder,
      GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
      &option);

  ghostty_key_event_set_action(ghostty_event, map_action(event->action));
  ghostty_key_event_set_key(ghostty_event, (GhosttyKey)event->key_code);
  ghostty_key_event_set_mods(ghostty_event, (GhosttyMods)event->mods);
  ghostty_key_event_set_consumed_mods(ghostty_event, (GhosttyMods)event->consumed_mods);
  ghostty_key_event_set_composing(ghostty_event, event->composing);
  ghostty_key_event_set_utf8(ghostty_event, event->utf8, event->utf8_len);
  ghostty_key_event_set_unshifted_codepoint(ghostty_event, event->unshifted_codepoint);

  const GhosttyResult encode_result = ghostty_key_encoder_encode(
      encoder,
      ghostty_event,
      out_buf,
      out_buf_size,
      out_len);
  ghostty_key_event_free(ghostty_event);
  ghostty_key_encoder_free(encoder);
  return (ite_ghostty_result_e)encode_result;
}
