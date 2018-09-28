defmodule Makrinos.HTTPAdapter do
  require Logger

  @compile :native
  @compile {:erl_opts, [native: :o3]}

  def call(req_uri, req_headers, rpc_method, rpc_params) do
    case batch_call(req_uri, req_headers, rpc_method, [rpc_params]) do
      {:ok, [resp]} -> resp
      batch_error   -> batch_error
    end
  end

  def batch_call(req_uri, req_headers, rpc_method, rpc_params_stream) do
    req_rpc_method = to_string(rpc_method)

    req_bodies = rpc_params_stream
    |> Stream.with_index
    |> Stream.map(fn({rpc_params, i}) ->
      %{
        "jsonrpc" => "2.0",
        "method" => req_rpc_method,
        "params" => rpc_params,
        "id" => (i + 1)
      }
    end)
    |> Stream.chunk_every(100)

    http_resps = Enum.map(req_bodies, fn(req_body) ->
      MachineGun.post(
        req_uri,
        Jason.encode_to_iodata!(req_body),
        req_headers,
        %{
          request_timeout: 1_200_000,
          follow_redirect: true,
          pool_group: :rpc_pool
        }
      )
    end)

    decode_batch_resps(http_resps)
  end

  defp decode_batch_resps(http_resps) do
    decode_batch_resps(http_resps, [])
  end
  defp decode_batch_resps([], decoded_resp_chunks) do
    parsed_resps = decoded_resp_chunks
    |> Enum.reverse
    |> Enum.concat
    |> Enum.map(&parse_response/1)

    {:ok, parsed_resps}
  end
  defp decode_batch_resps([http_resp | http_resps], acc) do
    case http_resp do
      {:ok, %{status_code: http_resp_code, body: http_resp_body}} when http_resp_code >= 200 and http_resp_code < 300 ->
        case Jason.decode!(http_resp_body) do
          %{"error" => %{"code" => batch_error_code, "message" => batch_error_msg}} ->
            batch_error({http_resp_code, batch_error_code}, batch_error_msg)

          decoded_resps when is_list(decoded_resps) ->
            decode_batch_resps(http_resps, [decoded_resps | acc])
        end

      {:ok, %{status_code: http_resp_code, body: http_resp_body}} ->
        batch_error(http_resp_code, http_resp_body)

      {:error, %MachineGun.Error{} = e} ->
        raise Makrinos.RPCError, e
    end
  end

  def parse_response(%{"error" => %{"code" => code, "message" => msg}}) do
    req_error(code, msg)
  end
  def parse_response(%{"result" => result}) do
    {:ok, result}
  end

  # raise on logic errors; return on environment errors; return if unsure
  def batch_error(401, _), do: {:unreachable, :endpoint, :forbidden}
  def batch_error(404, _), do: {:unreachable, :endpoint, :not_found}
  def batch_error(500, error_msg), do: {:server_error, 500, error_msg}
  def batch_error(502, _), do: {:unreachable, :peer, :gateway_error}
  def batch_error(503, _), do: {:unreachable, :peer, :overload}
  def batch_error({_, -32700}, _), do: raise Makrinos.RPCError, "client sent malformed JSON"
  def batch_error({_, -32600}, _), do: raise Makrinos.RPCError, "invalid request"
  def batch_error({_, -32601}, _), do: raise Makrinos.RPCError, "RPC endpoint not available"
  def batch_error({_, -32602}, _), do: raise Makrinos.RPCError, "invalid parameters"
  def batch_error({_, -32603}, msg), do: raise Makrinos.RPCError, {"internal JSON-RPC error", msg}
  def batch_error({_, code}, error_msg) when code >= -32099 and code <= -32000 do
    {:server_error, code, error_msg}
  end
  def batch_error({_, code}, error_msg) do
    {:unknown_error, code, error_msg}
  end
  def batch_error(code, msg) when code >= 400 and code < 500 do
    raise Makrinos.RPCError, {:client_error, msg}
  end
  def batch_error(code, msg) when code >= 500 and code < 600 do
    {:server_error, msg}
  end
  def batch_error(code, msg), do: {:unknown_error, code, msg}


  # client may be attempting methods to determine existence, so raise only if invalid syntactically
  def req_error(-32700, _), do: raise Makrinos.RPCError, "client sent malformed JSON"
  def req_error(-32600, _), do: raise Makrinos.RPCError, "invalid request"
  def req_error(-32601, _), do: {:unreachable, :endpoint, :not_found}
  def req_error(-32602, _), do: :invalid_parameters
  def req_error(-32603, msg), do: {:rpc_error, msg}
  def req_error(code, error_msg) when code >= -32099 and code <= -32000 do
    {:server_error, code, error_msg}
  end
  def req_error(code, error_msg) do
    {:unknown_error, code, error_msg}
  end
end
