defmodule Makrinos do
  def get_client(nil), do: unconfigured_client()

  def get_client(""), do: unconfigured_client()
  def get_client(uri) when is_binary(uri) do
    get_client(URI.parse(uri))
  end

  def get_client(%URI{scheme: nil, path: nil}), do: unconfigured_client()
  def get_client(%URI{scheme: scheme} = uri) do
    case scheme do
      "http" -> Makrinos.HTTPClient.get(uri)
      "https" -> Makrinos.HTTPClient.get(uri)
      "file" -> Makrinos.UDSClient.get(uri)
      nil -> Makrinos.UDSClient.get(uri)
    end
  end

  defp unconfigured_client() do
    Makrinos.DummyClient.with_status({:error, {:unreachable, :peer, :not_configured}})
  end
end
