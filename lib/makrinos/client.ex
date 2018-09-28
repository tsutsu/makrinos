defprotocol Makrinos.Client do
  def call(client, rpc_method, rpc_params)
  def batch_call(client, rpc_method, rpc_params_stream)
end
