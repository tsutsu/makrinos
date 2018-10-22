defmodule Makrinos.TCPAdapter do
  alias Makrinos.TCPTransport, as: Transport

  def start_link(uri, genserver_opts) do
    case Transport.start_link(uri, genserver_opts) do
      {:ok, transport_pid} ->
        {:ok, transport_pid}

      {:error, {:already_started, transport_pid}} ->
        {:ok, transport_pid}

      other_error ->
        other_error
    end
  end

  def call(transport_pid, rpc_method, rpc_params) do
    Transport.call(transport_pid, rpc_method, rpc_params)
  end

  def batch_call(transport_pid, rpc_method, rpc_params_stream) do
    Transport.batch_call(transport_pid, rpc_method, rpc_params_stream)
  end
end
