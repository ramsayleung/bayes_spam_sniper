require "ffi"
require "json"

# Minimal TDLib FFI wrapper, tdlib-ruby is conflict with
# telegram-bot-ruby as they depends on dry-core
module TDJson
  tdlib_path = ENV["TDLIB_PATH"]
  if Rails.env.development? && tdlib_path && !tdlib_path.empty?
    extend FFI::Library
    lib_name = "tdjson"
    if FFI::Platform.windows?
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "#{lib_name}.dll")
    elsif FFI::Platform.mac?
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "lib#{lib_name}.dylib")
    else
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "lib#{lib_name}.so")
    end

    attach_function :td_json_client_create, [], :pointer
    attach_function :td_json_client_send, [ :pointer, :string ], :void
    attach_function :td_json_client_receive, [ :pointer, :double ], :string
    attach_function :td_json_client_execute, [ :pointer, :string ], :string
    attach_function :td_json_client_destroy, [ :pointer ], :void
  end
end

class TdlibClient
  def initialize
    @client = TDJson.td_json_client_create
    @request_queue = {}
  end

  def send_async(query, &block)
    request_id = SecureRandom.uuid
    @request_queue[request_id] = block
    query["@extra"] = { request_id: request_id }.to_json
    TDJson.td_json_client_send(@client, JSON.dump(query))
  end

  def receive(timeout = 1.0)
    raw = TDJson.td_json_client_receive(@client, timeout)
    return unless raw

    update = JSON.parse(raw)
    if update["@extra"]
      extra = JSON.parse(update["@extra"])
      if extra["request_id"]
        callback = @request_queue.delete(extra["request_id"])
        callback.call(update) if callback
      end
    end
    update
  end

  def execute(query)
    raw = TDJson.td_json_client_execute(@client, JSON.dump(query))
    raw && JSON.parse(raw)
  end

  def send(query)
    TDJson.td_json_client_send(@client, JSON.dump(query))
  end

  def close
    TDJson.td_json_client_destroy(@client)
  end

  def get_chat(chat_id)
    execute({
              "@type" => "getChat",
              "chat_id" => chat_id
            })
  end

  def get_user(user_id)
    execute({
              "@type" => "getUser",
              "user_id" => user_id
            })
  end
end
