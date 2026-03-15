#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "ite_ghostty_wrapper.h"

static void assert_string_eq(const char *actual, size_t actual_len, const char *expected) {
  const size_t expected_len = strlen(expected);
  assert(actual_len == expected_len);
  assert(memcmp(actual, expected, expected_len) == 0);
}

int main(void) {
  assert(strcmp(
             ite_ghostty_vendor_snapshot(),
             "332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28")
         == 0);

  assert(ite_ghostty_paste_is_safe("hello", 5));
  assert(!ite_ghostty_paste_is_safe("rm -rf /\n", 9));

  char buffer[32];
  size_t out_len = 0;

  const ite_ghostty_key_event_s type_a = {
      .key_code = ite_ghostty_key_code_a(),
      .mods = 0,
      .consumed_mods = 0,
      .unshifted_codepoint = 'a',
      .utf8 = "a",
      .utf8_len = 1,
      .action = ITE_GHOSTTY_KEY_ACTION_PRESS,
      .composing = false,
  };
  assert(
      ite_ghostty_encode_key(
          &type_a,
          ITE_GHOSTTY_OPTION_AS_ALT_FALSE,
          buffer,
          sizeof(buffer),
          &out_len)
      == ITE_GHOSTTY_RESULT_SUCCESS);
  assert_string_eq(buffer, out_len, "a");

  const ite_ghostty_key_event_s press_enter = {
      .key_code = ite_ghostty_key_code_enter(),
      .mods = 0,
      .consumed_mods = 0,
      .unshifted_codepoint = '\r',
      .utf8 = "\r",
      .utf8_len = 1,
      .action = ITE_GHOSTTY_KEY_ACTION_PRESS,
      .composing = false,
  };
  assert(
      ite_ghostty_encode_key(
          &press_enter,
          ITE_GHOSTTY_OPTION_AS_ALT_FALSE,
          buffer,
          sizeof(buffer),
          &out_len)
      == ITE_GHOSTTY_RESULT_SUCCESS);
  assert_string_eq(buffer, out_len, "\r");

  puts("ghostty wrapper smoke ok");
  return 0;
}
