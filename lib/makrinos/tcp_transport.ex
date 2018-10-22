defmodule Makrinos.TCPTransport do
  use GenServer
  alias Makrinos.MessageFormat

  def start_link(uri, opts \\ [])
  def start_link(%URI{scheme: "tcp", host: host, port: port}, opts) when is_binary(host) and is_integer(port) do
    GenServer.start_link(__MODULE__, {:tcp_address, String.to_charlist(host), port}, opts)
  end
  def start_link(%URI{scheme: scheme, path: path}, opts) when scheme in ["file", nil] and is_binary(path) do
    GenServer.start_link(__MODULE__, {:file_path, path}, opts)
  end

  def call(socket_pid, method, params) do
    GenServer.call(socket_pid, {:rpc_request, :single, method, params}, :infinity)
  end

  def batch_call(socket_pid, method, params_list) do
    GenServer.call(socket_pid, {:rpc_request, :batch, method, params_list}, :infinity)
  end

  def shutdown(socket_pid) do
    GenServer.call(socket_pid, :shutdown)
  end


  def init({:file_path, path}) do
    init({:local, path}, 0, [:local])
  end
  def init({:tcp_address, hostname, port}) do
    init(hostname, port, [])
  end

  @default_tcp_opts [
    mode: :binary,
    packet: :line,
    active: true,
    send_timeout: 10_000,
    send_timeout_close: true
  ]

  @accept_timeout 5_000

  defp init(hostname, port, opts) do
    case :gen_tcp.connect(hostname, port, opts ++ @default_tcp_opts, @accept_timeout) do
      {:ok, socket} ->
        {:ok, %{
          config: {hostname, port, opts},
          socket: socket,
          next_req_id: 1,
          recv_buf: [],
          awaiting_response: Map.new
        }}

      {:error, :timeout} ->
        {:stop, {:unreachable, :peer, :timeout}}

      {:error, :nxdomain} ->
        {:stop, {:unreachable, :peer, :nxdomain}}
      {:error, :econnrefused} ->
        {:stop, {:unreachable, :peer, :econnrefused}}
      {:error, :enoent} ->
        {:stop, {:unreachable, :peer, :enoent}}
      {:error, :eacces} ->
        {:stop, {:unreachable, :peer, :eacces}}

      {:error, other_err} ->
        {:stop, other_err}
    end
  end

  def handle_call({:rpc_request, req_shape, method, params}, from, %{next_req_id: req_id, socket: socket} = state) do
    {msg, next_req_id} = MessageFormat.build_request(req_shape, method, params, req_id)

    # case req_shape do
    #   :single -> IO.puts("#{method}: #{inspect(params)}")
    #   :batch -> IO.puts("#{method} batch_rpc (x#{inspect(length(params))})")
    # end

    :gen_tcp.send(socket, msg)

    {:noreply, %{state |
      next_req_id: next_req_id,
      awaiting_response: Map.put(state.awaiting_response, req_id, {from, req_shape})
    }}
  end

  def handle_info({:tcp, socket, data}, %{socket: socket, awaiting_response: clients} = state) do
    resps = Jason.decode!(data) |> List.wrap

    req_id = resps |> List.first |> Map.fetch!("id")
    {{client_from, req_shape}, new_clients} = Map.pop(clients, req_id)

    resps = Enum.map(resps, &MessageFormat.parse_response/1)

    reply_msg = case req_shape do
      :batch  -> {:ok, resps}
      :single -> List.first(resps)
    end

    GenServer.reply(client_from, reply_msg)

    {:noreply, %{state | awaiting_response: new_clients}}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    {:stop, reason, state}
  end

  def handle_info(:shutdown, %{socket: socket} = state) do
    case :gen_tcp.shutdown(socket, :read_write) do
      :ok ->
        {:stop, :normal, state}
      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  def terminate(_reason, %{socket: socket}) do
    :gen_tcp.shutdown(socket, :read_write)
  end
end
