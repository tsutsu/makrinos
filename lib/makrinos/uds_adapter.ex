defmodule Makrinos.UDSAdapter do
  use GenServer
  alias :procket, as: Socket
  alias Makrinos.MessageFormat

  def call(uds_pid, method, params) do
    GenServer.call(uds_pid, {:rpc_request, :single, method, params}, :infinity)
  end

  def batch_call(uds_pid, method, params_list) do
    GenServer.call(uds_pid, {:rpc_request, :batch, method, params_list}, :infinity)
  end

  def start_link(path, opts \\ []) do
    if File.exists?(path) do
      GenServer.start_link(__MODULE__, path, opts)
    else
      {:error, :enoent}
    end
  end

  def init(path) when is_binary(path) do
    case open_unix_socket(Path.expand(path)) do
      {:ok, {fdin, fdout}} ->
        init(path, {fdin, fdout})

      {:error, :enoent} ->
        {:stop, :enoent}
    end
  end

  def init(path, {fdin, fdout}) do
    port = Port.open({:fd, fdin, fdout}, [:stream, :binary])
    Port.monitor(port)

    {:ok, %{
      path: path,
      port: port,
      next_req_id: 1,
      recv_buf: [],
      awaiting_response: Map.new
    }}
  end

  def handle_call({:rpc_request, req_shape, method, params}, from, %{next_req_id: req_id, port: port} = state) do
    {msg, next_req_id} = MessageFormat.build_request(req_shape, method, params, req_id)

    # case req_shape do
    #   :single -> IO.puts("#{method}: #{inspect(params)}")
    #   :batch -> IO.puts("#{method} batch_rpc (x#{inspect(length(params))})")
    # end

    Port.command(port, msg)

    {:noreply, %{state |
      next_req_id: next_req_id,
      awaiting_response: Map.put(state.awaiting_response, req_id, {from, req_shape})
    }}
  end

  def handle_info({port, {:data, data}}, %{port: port, recv_buf: recv_buf} = state) do
    recv_buf = packetize_received_data(recv_buf, data)
    {:noreply, %{state | recv_buf: recv_buf}}
  end

  def handle_info({:packetized_data, data}, %{awaiting_response: clients} = state) do
    resps = Jason.decode!(data) |> List.wrap

    req_id = resps |> List.first |> Map.fetch!("id")
    {{client_pid, req_shape}, new_clients} = Map.pop(clients, req_id)

    resps = Enum.map(resps, &MessageFormat.parse_response/1)

    reply_msg = case req_shape do
      :batch  -> {:ok, resps}
      :single -> List.first(resps)
    end

    GenServer.reply(client_pid, reply_msg)

    {:noreply, %{state | awaiting_response: new_clients}}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    {:stop, reason, state}
  end

  def terminate(_reason, %{port: port}) do
    Port.close(port)
  catch _, _ -> :ok
  end

  defp packetize_received_data(recv_buf, data) do
    case :binary.split(data, "\n") do
      [leftover] -> [leftover | recv_buf]

      [line, more] ->
        packet = [line | recv_buf] |> Enum.reverse
        self() |> send({:packetized_data, packet})
        packetize_received_data([], more)
    end
  end

  @uds_socket_family 1

  defp open_unix_socket(path) do
    pad = 8 * (Socket.unix_path_max - byte_size(path))
    sockaddr = Socket.sockaddr_common(@uds_socket_family, byte_size(path)) <> path <> <<0::size(pad)>>

    {:ok, socket} = Socket.socket(@uds_socket_family, 1, 0)

    case Socket.connect(socket, sockaddr) do
      :ok -> {:ok, {socket, socket}}
      {:error, :einprogress} -> {:ok, {socket, socket}}
      {:error, err} -> {:error, err}
    end
  end
end
