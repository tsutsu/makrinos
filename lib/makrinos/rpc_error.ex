defmodule Makrinos.RPCError do
  defexception [:message]

  def exception(error) do
    msg = "RPC error: #{inspect error}"
    %__MODULE__{message: msg}
  end
end
