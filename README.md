# Makrinos

An Elixir JSON-RPC client library focusing on high-throughput, low-overhead messaging.

In service of lowering overhead, Makrinos supports:

* the JSON-RPC batched-request API
* a Unix domain-socket (UDS) transport, as well as an HTTP transport

Makrinos aims to be the fastest Elixir JSON-RPC client. If another client is faster, that's a bug.

## Installation

The package can be installed by adding `makrinos` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:makrinos, "~> 0.1.0"}
  ]
end
```

## Usage

Makrinos has a protocol, `Makrinos.Client`, which is implemented by the concrete clients that implement each transport, namely `Makrinos.HTTPClient` and `Makrinos.UDSClient`.

### Creating a client

All clients support only one creation function `get/1`, which is memoized. Any time you need the client, `get/1` it, passing the same parameters you would if you were creating it anew:

```elixir
http_client = Makrinos.HTTPClient.get("http://user:pass@host:4581")
```

```elixir
uds_client = Makrinos.UDSClient.get("/path/to/socket")
```

Each client transport implements memoization differently, but to roughly the same effect. The UDS client is actually memoized (i.e. you are retrieving the PID of a process based on the passed path), while the HTTP client returns a new `%Makrinos.HTTPClient{}` data-structure, but using it to make calls will rely on a per-destination connection pool (from [`machine_gun`](https://github.com/petrohi/machine_gun)), which serves to decrease the cost of building new connections.

##### Optimizing client creation

The `get/1` function still does have some small overhead, due to needing to canonicalize the passed parameter before using it as a memoization key. If you wish to reduce overhead even further, we recommended pre-parsing and caching the parameter for `get/1`.

The API for `get/1` was designed to work with a "preconfigured" decorator module, one that can cheaply-and-efficiently supply a pre-parsed parameter to `get/1`.

Options for holding and passing a pre-parsed parameter within such a decorator module include using [Confex](https://github.com/Nebo15/confex) with a `Confex.Adapter`, and using [fastglobal](https://github.com/discordapp/fastglobal), but for the sake of demonstration, here's the simplest-but-dirtiest solution—reading an OS env-var at compile-time, and so baking the pre-parsed URI into the compiled module:

```elixir
defmodule MyPreconfiguredClient do
  @client_uri URI.parse(System.get_env("REMOTE_CONN"))

  defp get_client, do:
    Makrinos.HTTPClient.get(@client_uri)

  def call(rpc_method, rpc_params), do:
    get_client().call(rpc_method, rpc_params)

  def batch_call(rpc_method, rpc_params_stream), do:
    get_client().batch_call(rpc_method, rpc_params_stream)
end
```

### Making simple requests

Let's pretend we have a JSON-RPC endpoint method to interact with called "count", which takes a single integer parameter `count_to`, and returns a list of the natural numbers starting from 1 up to `count_to`.

A simple, one-off request to that endpoint would look like:

```elixir
iex> Makrinos.Client.call(client, :count, [4])
{:ok, [1, 2, 3, 4]}
```

### Making batched requests

Makrinos supports a limited subset of the JSON-RPC batched-request API. This subset was chosen for its cheap JSON generation and intuitive batchwise error-handling. (Also, we've found that it's the only type of batched request that's worth the trouble.)

Rather than supporting arbitrary sequences of `{rpc_method, rpc_params}` requests within a batched request, instead, the `Makrinos.Client.batch_call/3` function expects a single `rpc_method`, which applies to all the requests in the batch. Together with the single `rpc_method` is passed an Enumerable of RPC parameter lists. Each request in the batched request is created by pairing the RPC method with one of the RPC parameter lists.

Assuming the same JSON-RPC endpoint method "count" from above, here's the way to make the same request as above, using a batched request containing a single request:

```elixir
iex> Makrinos.Client.batch_call(client, :count, [[4]])
{:ok, [ok: [1, 2, 3, 4]]}
```

Note how the response has been tagged **twice**—a batched request results in a response (the success or failure of the batched request as a whole, which can fail for syntactic or network-transport reasons); and that response, if successful, contains a list of responses, detailing the success or failure of each request made within the batch.

Here's a more complex batched request, containing both an invalid and a valid-but-failed request:
```elixir
iex> Makrinos.Client.batch_call(client, :count, [[4], [2], [], [0], [5]])
{:ok, [
  {:ok, [1, 2, 3, 4]},
  {:ok, [1, 2]},
  :invalid_parameters,
  {:ok, %{"error" => "OutOfRangeException"}}
  {:ok, [1, 2, 3, 4, 5]},
]}
```

### Error-handling

A JSON-RPC request can raise many types of errors: JSON decoding errors, transport errors (i.e. HTTP protocol errors, or POSIX system-call errors for domain sockets), JSON-RPC specific errors, *domain-specific errors* that some JSON-RPC servers may have chosen to use, and, of course, business-layer errors encoded within a valid return value.

Errors that can be summed up as "you, the programmer, made a mistake" are bubbled up as `Makrinos.RPCError` exceptions to oh-so-helpfully crash your problematic code. The rest are returned as-is.

A list of non-exception error responses you may see in response to a `call/3` or `batch_call/3`:

| Error term                       | Description                                                  |
| -------------------------------- | ------------------------------------------------------------ |
| `:invalid_parameters`            | If returned for a particular request within a batched request, the server considered the particular request to have a type or arity error in the supplied parameters.<br /><br />When making single requests with `call/3`, this error is instead assumed to be programmer error and so raises an exception. |
| `{:unreachable, :endpoint, :forbidden}` | An HTTP 401 error was encountered while making the request over an HTTP transport. |
| `{:unreachable, :endpoint, :not_found}` | An HTTP 404 error was encountered while making the request over an HTTP transport.<br /><br />If returned for a particular request within a batched request, the server considered the particular request to require an unavailable resource. |
| `{:unreachable, :peer, :gateway_error}` | An HTTP 502 error was encountered while making the request over an HTTP transport. |
| `{:unreachable, :peer, :overload}` | An HTTP 503 error was encountered while making the request over an HTTP transport.<br /><br />If you are using a circuit-breaker library like [ExternalService](https://github.com/jvoegele/external_service), it is recommended to write a wrapper function to coalesce this error into the circuit breaker's `{:error, :fuse_blown}` error, since they should be handled the same way by callers. |
| `{:unreachable, :peer, :no_connection}` | The transport failed to submit the request to the remote.<br /><br />For the HTTP transport, this corresponds to a DNS resolution error, as well as to any TCP-level failures before managing to POST the request. <br />For the UDS transport, this corresponds to a non-existent or un-openable socket file. |
| `{:unreachable, :peer, :not_configured}` | The transport was not configured correctly.<br /><br />Both the HTTP and UDS transports allow the developer to pass a `nil` parameter to `get/1`. This will return a dummy client that responds to all requests with `{:unreachable, :peer, :not_configured}`. This can be useful when your JSON-RPC API access feeds an *optional* feature, and you wish to allow the system administrator the choice of whether to configure the client (and so enable the feature) or not. |
| `{:server_error, code, msg}`     | Either the transport layer, or the JSON-RPC protocol layer, has failed on the server side. An HTTP 500 error is reported as a `{:server_error, 500, msg}`. JSON-RPC error codes between `-32099` and `-32000` are also reported as server errors. |
| `{:rpc_error, msg}`              | The JSON-RPC protocol layer has failed on the client side, but not due to programmer error. |
| `{:unknown_error, code, msg}`    | Any other HTTP or JSON-RPC error code will be presented as an `:unknown_error`. |
