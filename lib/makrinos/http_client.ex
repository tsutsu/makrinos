defmodule Makrinos.HTTPClient do
  defstruct [:request_uri, :request_headers]
  alias Makrinos.HTTPAdapter, as: Adapter

  def get(conn_uri) when is_binary(conn_uri) do
    get(URI.parse(conn_uri))
  end
  def get(%URI{} = conn_uri) do
    req_uri = %{path: "/"}
    |> Map.merge(conn_uri)
    |> Map.put(:userinfo, nil)

    auth_headers = case conn_uri.userinfo do
      "" -> []
      nil -> []
      userinfo -> [{"Authorization", "Basic " <> Base.encode64(userinfo)}]
    end

    req_headers = auth_headers ++ [
      {"host", conn_uri.host},
      {"content-type", "application/json"}
    ]

    %__MODULE__{request_uri: URI.to_string(req_uri), request_headers: req_headers}
  end

  defimpl Makrinos.Client do
    def call(client, rpc_method, rpc_params) do
      Adapter.call(client.request_uri, client.request_headers, rpc_method, rpc_params)
    end

    def batch_call(client, rpc_method, rpc_params_stream) do
      Adapter.batch_call(client.request_uri, client.request_headers, rpc_method, rpc_params_stream)
    end
  end
end
