#ifndef ITE_GHOSTTY_WRAPPER_H
#define ITE_GHOSTTY_WRAPPER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  ITE_GHOSTTY_RESULT_SUCCESS = 0,
  ITE_GHOSTTY_RESULT_OUT_OF_MEMORY = -1,
  ITE_GHOSTTY_RESULT_INVALID_VALUE = -2,
} ite_ghostty_result_e;

typedef enum {
  ITE_GHOSTTY_KEY_ACTION_RELEASE = 0,
  ITE_GHOSTTY_KEY_ACTION_PRESS = 1,
  ITE_GHOSTTY_KEY_ACTION_REPEAT = 2,
} ite_ghostty_key_action_e;

typedef enum {
  ITE_GHOSTTY_OPTION_AS_ALT_FALSE = 0,
  ITE_GHOSTTY_OPTION_AS_ALT_TRUE = 1,
  ITE_GHOSTTY_OPTION_AS_ALT_LEFT = 2,
  ITE_GHOSTTY_OPTION_AS_ALT_RIGHT = 3,
} ite_ghostty_option_as_alt_e;

typedef struct {
  uint16_t key_code;
  uint16_t mods;
  uint16_t consumed_mods;
  uint32_t unshifted_codepoint;
  const char *utf8;
  size_t utf8_len;
  uint8_t action;
  bool composing;
} ite_ghostty_key_event_s;

const char *ite_ghostty_vendor_snapshot(void);
uint16_t ite_ghostty_key_code_a(void);
uint16_t ite_ghostty_key_code_enter(void);
bool ite_ghostty_paste_is_safe(const char *data, size_t len);
ite_ghostty_result_e ite_ghostty_encode_key(
    const ite_ghostty_key_event_s *event,
    ite_ghostty_option_as_alt_e option_as_alt,
    char *out_buf,
    size_t out_buf_size,
    size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif
