defmodule Makrinos.TCPClient do
  defstruct [:uri, :resource]
  alias Makrinos.TCPAdapter, as: Adapter

  def get(uri) when is_binary(uri) do
    get(URI.parse(uri))
  end
  def get(%URI{} = uri) do
    own_name = {:via, Registry, {Makrinos.Registry, uri}}

    case Adapter.start_link(uri, name: own_name) do
      {:ok, resource} ->
        %__MODULE__{uri: uri, resource: resource}

      {:error, {:unreachable, :peer, posix_err}} ->
        Makrinos.DummyClient.with_status({:error, {:unreachable, :peer, posix_err}})
    end
  end

  defimpl Makrinos.Client do
    def call(%{resource: resource}, rpc_method, rpc_params) do
      Adapter.call(resource, rpc_method, rpc_params)
    end

    def batch_call(%{resource: resource}, rpc_method, rpc_params_stream) do
      Adapter.batch_call(resource, rpc_method, rpc_params_stream)
    end
  end
end
