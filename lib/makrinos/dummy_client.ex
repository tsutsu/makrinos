defmodule Makrinos.DummyClient do
  defstruct status: nil

  def with_status(status) do
    %__MODULE__{status: status}
  end

  defimpl Makrinos.Client do
    def call(%Makrinos.DummyClient{status: status}, _rpc_method, _rpc_params) do
      status
    end

    def batch_call(%Makrinos.DummyClient{status: status}, _rpc_method, _rpc_params_stream) do
      status
    end
  end
end
