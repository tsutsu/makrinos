defmodule Makrinos.UDSClient do
  defstruct [:connection_status, :path, :socket_pid]
  alias Makrinos.UDSAdapter, as: Adapter

  def get(nil) do
    %__MODULE__{connection_status: {:unreachable, :peer, :not_configured}}
  end
  def get(socket_path) when is_binary(socket_path) do
    own_name = {:via, Registry, {Makrinos.Registry, socket_path}}

    case Adapter.start_link(socket_path, name: own_name) do
      {:ok, socket_pid} ->
        %__MODULE__{connection_status: :ok, path: socket_path, socket_pid: socket_pid}

      {:error, {:already_started, socket_pid}} ->
        %__MODULE__{connection_status: :ok, path: socket_path, socket_pid: socket_pid}

      {:error, :enoent} ->
        %__MODULE__{connection_status: {:unreachable, :peer, :no_connection}}
    end
  end

  defimpl Makrinos.Client do
    def call(%{connection_status: :ok} = client, rpc_method, rpc_params) do
      Adapter.call(client.socket_pid, rpc_method, rpc_params)
    end
    def call(%{connection_status: status}, _rpc_method, _rpc_params) do
      status
    end

    def batch_call(%{connection_status: :ok} = client, rpc_method, rpc_params_stream) do
      Adapter.batch_call(client.socket_pid, rpc_method, rpc_params_stream)
    end
    def batch_call(%{connection_status: status} = _client, _rpc_method, _rpc_params_stream) do
      status
    end
  end
end
