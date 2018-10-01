defmodule Makrinos.MessageFormat do
  def build_request(req_shape, rpc_method, rpc_params, req_id \\ 1)

  def build_request(:single, rpc_method, rpc_params, req_id) do
    req = %{
      "jsonrpc" => "2.0",
      "method" => to_string(rpc_method),
      "params" => rpc_params,
      "id" => req_id
    }

    {Jason.encode_to_iodata!(req), req_id + 1}
  end

  def build_request(:batch, rpc_method, rpc_params_list, base_req_id) do
    rpc_method = to_string(rpc_method)

    batch_req = rpc_params_list
    |> Stream.with_index
    |> Stream.map(fn({rpc_params, req_id_offset}) ->
      %{
        "jsonrpc" => "2.0",
        "method" => rpc_method,
        "params" => rpc_params,
        "id" => base_req_id + req_id_offset
      }
    end)
    |> Enum.to_list

    next_base_req_id = base_req_id + length(batch_req)

    {Jason.encode_to_iodata!(batch_req), next_base_req_id}
  end

  def parse_response_json(resp_json_iodata) do
    resp_json_iodata
    |> Jason.decode!
    |> parse_response
  end

  def parse_response(%{"error" => %{"code" => code, "message" => msg}}) do
    req_error(code, msg)
  end
  def parse_response(%{"result" => result}) do
    {:ok, result}
  end

  def parse_response(resps) when is_list(resps) do
    Enum.map(resps, &parse_response/1)
  end

  # client may be attempting methods to determine existence, so raise only if invalid syntactically
  def req_error(-32700, _), do: raise ArgumentError, "client sent malformed JSON"
  def req_error(-32600, _), do: raise ArgumentError, "invalid request"
  def req_error(-32601, _), do: {:error, {:unreachable, :endpoint, :not_found}}
  def req_error(-32602, _), do: {:error, :invalid_parameters}
  def req_error(-32603, msg), do: {:error, {:rpc_error, msg}}
  def req_error(code, error_msg) when code >= -32099 and code <= -32000 do
    {:error, {:server_error, code, error_msg}}
  end
  def req_error(code, error_msg) do
    {:error, {:unknown_error, code, error_msg}}
  end
end
