#include <ruby.h>
#include <ruby/thread.h>
#include <ddprof/ffi.h>
#include "libddprof_helpers.h"
#include "ruby_helpers.h"

// Used to report profiling data to Datadog.
// This file implements the native bits of the Datadog::Profiling::HttpTransport class

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

static ID agentless_id; // id of :agentless in Ruby
static ID agent_id; // id of :agent in Ruby

static ID log_failure_to_process_tag_id; // id of :log_failure_to_process_tag in Ruby

static VALUE http_transport_class = Qnil;

struct call_exporter_without_gvl_arguments {
  ddprof_ffi_ProfileExporterV3 *exporter;
  ddprof_ffi_Request *request;
  ddprof_ffi_CancellationToken *cancel_token;
  ddprof_ffi_SendResult result;
  bool send_ran;
};

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string);
static VALUE _native_validate_exporter(VALUE self, VALUE exporter_configuration);
static ddprof_ffi_NewProfileExporterV3Result create_exporter(VALUE exporter_configuration, VALUE tags_as_array);
static VALUE handle_exporter_failure(ddprof_ffi_NewProfileExporterV3Result exporter_result);
static ddprof_ffi_EndpointV3 endpoint_from(VALUE exporter_configuration);
static ddprof_ffi_Vec_tag convert_tags(VALUE tags_as_array);
static void safely_log_failure_to_process_tag(ddprof_ffi_Vec_tag tags, VALUE err_details);
static VALUE _native_do_export(
  VALUE self,
  VALUE exporter_configuration,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data,
  VALUE tags_as_array
);
static void *call_exporter_without_gvl(void *call_args);
static void interrupt_exporter_call(void *cancel_token);

void http_transport_init(VALUE profiling_module) {
  http_transport_class = rb_define_class_under(profiling_module, "HttpTransport", rb_cObject);

  rb_define_singleton_method(http_transport_class, "_native_validate_exporter",  _native_validate_exporter, 1);
  rb_define_singleton_method(http_transport_class, "_native_do_export",  _native_do_export, 11);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));
  agentless_id = rb_intern_const("agentless");
  agent_id = rb_intern_const("agent");
  log_failure_to_process_tag_id = rb_intern_const("log_failure_to_process_tag");
}

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_ByteSlice byte_slice = {.ptr = (uint8_t *) StringValuePtr(string), .len = RSTRING_LEN(string)};
  return byte_slice;
}

static VALUE _native_validate_exporter(VALUE self, VALUE exporter_configuration) {
  Check_Type(exporter_configuration, T_ARRAY);
  ddprof_ffi_NewProfileExporterV3Result exporter_result = create_exporter(exporter_configuration, rb_ary_new());

  VALUE failure_tuple = handle_exporter_failure(exporter_result);
  if (!NIL_P(failure_tuple)) return failure_tuple;

  // We don't actually need the exporter for now -- we just wanted to validate that we could create it with the
  // settings we were given
  ddprof_ffi_NewProfileExporterV3Result_drop(exporter_result);

  return rb_ary_new_from_args(2, ok_symbol, Qnil);
}

static ddprof_ffi_NewProfileExporterV3Result create_exporter(VALUE exporter_configuration, VALUE tags_as_array) {
  Check_Type(exporter_configuration, T_ARRAY);
  Check_Type(tags_as_array, T_ARRAY);

  // This needs to be called BEFORE convert_tags since it can raise an exception and thus cause the ddprof_ffi_Vec_tag
  // to be leaked.
  ddprof_ffi_EndpointV3 endpoint = endpoint_from(exporter_configuration);

  ddprof_ffi_Vec_tag tags = convert_tags(tags_as_array);

  ddprof_ffi_NewProfileExporterV3Result exporter_result =
    ddprof_ffi_ProfileExporterV3_new(DDPROF_FFI_CHARSLICE_C("ruby"), &tags, endpoint);

  ddprof_ffi_Vec_tag_drop(tags);

  return exporter_result;
}

static VALUE handle_exporter_failure(ddprof_ffi_NewProfileExporterV3Result exporter_result) {
  if (exporter_result.tag == DDPROF_FFI_NEW_PROFILE_EXPORTER_V3_RESULT_OK) return Qnil;

  VALUE err_details = ruby_string_from_vec_u8(exporter_result.err);

  ddprof_ffi_NewProfileExporterV3Result_drop(exporter_result);

  return rb_ary_new_from_args(2, error_symbol, err_details);
}

static ddprof_ffi_EndpointV3 endpoint_from(VALUE exporter_configuration) {
  Check_Type(exporter_configuration, T_ARRAY);

  ID working_mode = SYM2ID(rb_ary_entry(exporter_configuration, 0)); // SYM2ID verifies its input so we can do this safely

  if (working_mode != agentless_id && working_mode != agent_id) {
    rb_raise(rb_eArgError, "Failed to initialize transport: Unexpected working mode, expected :agentless or :agent");
  }

  if (working_mode == agentless_id) {
    VALUE site = rb_ary_entry(exporter_configuration, 1);
    VALUE api_key = rb_ary_entry(exporter_configuration, 2);
    Check_Type(site, T_STRING);
    Check_Type(api_key, T_STRING);

    return ddprof_ffi_EndpointV3_agentless(char_slice_from_ruby_string(site), char_slice_from_ruby_string(api_key));
  } else { // agent_id
    VALUE base_url = rb_ary_entry(exporter_configuration, 1);
    Check_Type(base_url, T_STRING);

    return ddprof_ffi_EndpointV3_agent(char_slice_from_ruby_string(base_url));
  }
}

__attribute__((warn_unused_result))
static ddprof_ffi_Vec_tag convert_tags(VALUE tags_as_array) {
  Check_Type(tags_as_array, T_ARRAY);

  long tags_count = RARRAY_LEN(tags_as_array);
  ddprof_ffi_Vec_tag tags = ddprof_ffi_Vec_tag_new();

  for (long i = 0; i < tags_count; i++) {
    VALUE name_value_pair = rb_ary_entry(tags_as_array, i);

    if (!RB_TYPE_P(name_value_pair, T_ARRAY)) {
      ddprof_ffi_Vec_tag_drop(tags);
      Check_Type(name_value_pair, T_ARRAY);
    }

    // Note: We can index the array without checking its size first because rb_ary_entry returns Qnil if out of bounds
    VALUE tag_name = rb_ary_entry(name_value_pair, 0);
    VALUE tag_value = rb_ary_entry(name_value_pair, 1);

    if (!(RB_TYPE_P(tag_name, T_STRING) && RB_TYPE_P(tag_value, T_STRING))) {
      ddprof_ffi_Vec_tag_drop(tags);
      Check_Type(tag_name, T_STRING);
      Check_Type(tag_value, T_STRING);
    }

    ddprof_ffi_PushTagResult push_result =
      ddprof_ffi_Vec_tag_push(&tags, char_slice_from_ruby_string(tag_name), char_slice_from_ruby_string(tag_value));

    if (push_result.tag == DDPROF_FFI_PUSH_TAG_RESULT_ERR) {
      VALUE err_details = ruby_string_from_vec_u8(push_result.err);
      ddprof_ffi_PushTagResult_drop(push_result);

      // libddprof validates tags and may catch invalid tags that ddtrace didn't actually catch.
      // We warn users about such tags, and then just ignore them.
      safely_log_failure_to_process_tag(tags, err_details);
    } else {
      ddprof_ffi_PushTagResult_drop(push_result);
    }
  }

  return tags;
}

static VALUE log_failure_to_process_tag(VALUE err_details) {
  return rb_funcall(http_transport_class, log_failure_to_process_tag_id, 1, err_details);
}

// Since we are calling into Ruby code, it may raise an exception. This method ensure that dynamically-allocated tags
// get cleaned before propagating the exception.
static void safely_log_failure_to_process_tag(ddprof_ffi_Vec_tag tags, VALUE err_details) {
  int exception_state;
  rb_protect(log_failure_to_process_tag, err_details, &exception_state);

  if (exception_state) {           // An exception was raised
    ddprof_ffi_Vec_tag_drop(tags); // clean up
    rb_jump_tag(exception_state);  // "Re-raise" exception
  }
}

// Note: This function handles a bunch of libddprof dynamically-allocated objects, so it MUST not use any Ruby APIs
// which can raise exceptions, otherwise the objects will be leaked.
static VALUE perform_export(
  ddprof_ffi_NewProfileExporterV3Result valid_exporter_result, // Must be called with a valid exporter result
  ddprof_ffi_Timespec start,
  ddprof_ffi_Timespec finish,
  ddprof_ffi_Slice_file slice_files,
  ddprof_ffi_Vec_tag *additional_tags,
  uint64_t timeout_milliseconds
) {
  ddprof_ffi_ProfileExporterV3 *exporter = valid_exporter_result.ok;
  ddprof_ffi_CancellationToken *cancel_token = ddprof_ffi_CancellationToken_new();
  ddprof_ffi_Request *request =
    ddprof_ffi_ProfileExporterV3_build(exporter, start, finish, slice_files, additional_tags, timeout_milliseconds);

  // We'll release the Global VM Lock while we're calling send, so that the Ruby VM can continue to work while this
  // is pending
  struct call_exporter_without_gvl_arguments args =
    {.exporter = exporter, .request = request, .cancel_token = cancel_token, .send_ran = false};

  // We use rb_thread_call_without_gvl2 instead of rb_thread_call_without_gvl as the gvl2 variant never raises any
  // exceptions.
  //
  // (With rb_thread_call_without_gvl, if someone calls Thread#kill or something like it on the current thread,
  // the exception will be raised without us being able to clean up dynamically-allocated stuff, which would leak.)
  //
  // Instead, we take care of our own exception checking, and delay the exception raising (`rb_jump_tag` call) until
  // after we cleaned up any dynamically-allocated resources.
  //
  // We run rb_thread_call_without_gvl2 in a loop since an "interrupt" may cause it to return before even running
  // our code. In such a case, we retry the call -- unless the interrupt was caused by an exception being pending,
  // and in that case we also give up and break out of the loop.
  int pending_exception = 0;

  while (!args.send_ran && !pending_exception) {
    rb_thread_call_without_gvl2(call_exporter_without_gvl, &args, interrupt_exporter_call, cancel_token);
    if (!args.send_ran) pending_exception = check_if_pending_exception();
  }

  VALUE ruby_status;
  VALUE ruby_result;

  if (pending_exception) {
    // We're in a weird situation that libddprof doesn't quite support. The ddprof_ffi_Request payload is dynamically
    // allocated and needs to be freed, but libddprof doesn't have an API for dropping a request.
    //
    // There's plans to add a `ddprof_ffi_Request_drop`
    // (https://github.com/DataDog/dd-trace-rb/pull/1923#discussion_r882096221); once that happens, we can use it here.
    //
    // As a workaround, we get libddprof to clean up the request by asking for the send to be cancelled, and then calling
    // it anyway. This will make libddprof free the request and return immediately which gets us the expected effect.
    interrupt_exporter_call((void *) cancel_token);
    call_exporter_without_gvl((void *) &args);
  }

  ddprof_ffi_SendResult result = args.result;
  bool success = result.tag == DDPROF_FFI_SEND_RESULT_HTTP_RESPONSE;

  ruby_status = success ? ok_symbol : error_symbol;
  ruby_result = success ? UINT2NUM(result.http_response.code) : ruby_string_from_vec_u8(result.failure);

  // Clean up all dynamically-allocated things
  ddprof_ffi_SendResult_drop(args.result);
  ddprof_ffi_CancellationToken_drop(cancel_token);
  ddprof_ffi_NewProfileExporterV3Result_drop(valid_exporter_result);
  // The request itself does not need to be freed as libddprof takes care of it.

  // We've cleaned up everything, so if there's an exception to be raised, let's have it
  if (pending_exception) rb_jump_tag(pending_exception);

  return rb_ary_new_from_args(2, ruby_status, ruby_result);
}

static VALUE _native_do_export(
  VALUE self,
  VALUE exporter_configuration,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data,
  VALUE tags_as_array
) {
  Check_Type(upload_timeout_milliseconds, T_FIXNUM);
  Check_Type(start_timespec_seconds, T_FIXNUM);
  Check_Type(start_timespec_nanoseconds, T_FIXNUM);
  Check_Type(finish_timespec_seconds, T_FIXNUM);
  Check_Type(finish_timespec_nanoseconds, T_FIXNUM);
  Check_Type(pprof_file_name, T_STRING);
  Check_Type(pprof_data, T_STRING);
  Check_Type(code_provenance_file_name, T_STRING);

  // Code provenance can be disabled and in that case will be set to nil
  bool have_code_provenance = !NIL_P(code_provenance_data);
  if (have_code_provenance) Check_Type(code_provenance_data, T_STRING);

  uint64_t timeout_milliseconds = NUM2ULONG(upload_timeout_milliseconds);

  ddprof_ffi_Timespec start =
    {.seconds = NUM2LONG(start_timespec_seconds), .nanoseconds = NUM2UINT(start_timespec_nanoseconds)};
  ddprof_ffi_Timespec finish =
    {.seconds = NUM2LONG(finish_timespec_seconds), .nanoseconds = NUM2UINT(finish_timespec_nanoseconds)};

  int files_to_report = 1 + (have_code_provenance ? 1 : 0);
  ddprof_ffi_File files[files_to_report];
  ddprof_ffi_Slice_file slice_files = {.ptr = files, .len = files_to_report};

  files[0] = (ddprof_ffi_File) {
    .name = char_slice_from_ruby_string(pprof_file_name),
    .file = byte_slice_from_ruby_string(pprof_data)
  };
  if (have_code_provenance) {
    files[1] = (ddprof_ffi_File) {
      .name = char_slice_from_ruby_string(code_provenance_file_name),
      .file = byte_slice_from_ruby_string(code_provenance_data)
    };
  }

  ddprof_ffi_Vec_tag *null_additional_tags = NULL;

  ddprof_ffi_NewProfileExporterV3Result exporter_result = create_exporter(exporter_configuration, tags_as_array);
  // Note: Do not add anything that can raise exceptions after this line, as otherwise the exporter memory will leak

  VALUE failure_tuple = handle_exporter_failure(exporter_result);
  if (!NIL_P(failure_tuple)) return failure_tuple;

  return perform_export(exporter_result, start, finish, slice_files, null_additional_tags, timeout_milliseconds);
}

static void *call_exporter_without_gvl(void *call_args) {
  struct call_exporter_without_gvl_arguments *args = (struct call_exporter_without_gvl_arguments*) call_args;

  args->result = ddprof_ffi_ProfileExporterV3_send(args->exporter, args->request, args->cancel_token);
  args->send_ran = true;

  return NULL; // Unused
}

// Called by Ruby when it wants to interrupt call_exporter_without_gvl above, e.g. when the app wants to exit cleanly
static void interrupt_exporter_call(void *cancel_token) {
  ddprof_ffi_CancellationToken_cancel((ddprof_ffi_CancellationToken *) cancel_token);
}
