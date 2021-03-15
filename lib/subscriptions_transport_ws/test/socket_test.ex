defmodule SubscriptionsTransportWS.SocketTest do
  @moduledoc """
  Helper module for testing socket behaviours.

  ## Usage

  ```elixir
  # Example socket
  defmodule GraphqlSocket do
    use SubscriptionsTransportWS.Socket, schema: TestSchema, keep_alive: 10

    @impl true
    def connect(params, socket) do
      {:ok, socket}
    end

    @impl true
    def gql_connection_init(message, socket) do
      {:ok, socket}
    end
  end

  # Endpoint routes to the socket
  defmodule YourApp.Endpoint do
    use Phoenix.Endpoint, otp_app: :subscription_transport_ws
    use Absinthe.Phoenix.Endpoint

    socket("/ws", GraphqlSocket, websocket: [subprotocols: ["graphql-ws"]])
    # ... rest of your endpoint
  end

  # Test suite
  defmodule SomeTest do
    use ExUnit.Case
    import SubscriptionsTransportWS.SocketTest

    @endpoint YourApp.Endpoint

    test "a test" do
      socket(GraphqlSocket, TestSchema)

      # Push query over socket and receive response
      assert {:ok, %{"data" => %{"posts" => [%{"body" => "body1", "id" => "aa"}]}}, _socket} = push_doc(socket, "query {
        posts {
          id
          body
        }
      }", variables: %{limit: 10})


      # Subscribe to subscription
      {:ok, socket} = push_doc(socket, "subscription {
          postAdded{
            id
            body
            title
          }
      }", variables: %{})

    end
  end
  ```
  """
  alias Phoenix.Socket.V2.JSONSerializer
  alias SubscriptionsTransportWS.OperationMessage
  alias SubscriptionsTransportWS.Socket

  @doc """
  Helper function to build a socket.

  ## Example
    ```elixir
    iex> socket = socket(GraphqlSocket, TestSchema)
    ```
  """
  defmacro socket(socket_module, schema) do
    build_socket(socket_module, [], schema, __CALLER__)
  end

  defp build_socket(socket_module, assigns, schema, caller) do
    if endpoint = Module.get_attribute(caller.module, :endpoint) do
      quote do
        %Socket{
          assigns:
            Enum.into(unquote(assigns), %{
              absinthe: %{
                opts: [context: %{pubsub: unquote(endpoint)}],
                schema: unquote(schema),
                pipeline: {SubscriptionsTransportWS.Socket, :default_pipeline}
              }
            }),
          endpoint: unquote(endpoint),
          handler: unquote(socket_module),
          json_module: Jason,
          pubsub_server: unquote(caller.module)
        }
      end
    else
      raise "module attribute @endpoint not set for socket/2"
    end
  end

  @doc """
  Initiates a transport connection for the socket handler.
  Useful for testing UserSocket authentication. Returns
  the result of the handler's `connect/3` callback.
  """
  defmacro connect(handler, params, connect_info \\ quote(do: %{})) do
    if endpoint = Module.get_attribute(__CALLER__.module, :endpoint) do
      quote do
        unquote(__MODULE__).__connect__(
          unquote(endpoint),
          unquote(handler),
          unquote(params),
          unquote(connect_info)
        )
      end
    else
      raise "module attribute @endpoint not set for socket/2"
    end
  end

  @doc """
  Helper function to receive subscription data over the socket

  ## Example
  ```elixir
  push_doc(socket, "mutation submitPost($title: String, $body: String){
        submitPost(title: $title, body: $body){
          id
          body
          title

        }
      }", variables: %{title: "test title", body: "test body"})

  assert_receive_subscription %{
    "data" => %{
      "postAdded" => %{"body" => "test body", "id" => "1", "title" => "test title"}
    }
  }
  ```
  """
  defmacro assert_receive_subscription(
             payload,
             timeout \\ Application.fetch_env!(:ex_unit, :assert_receive_timeout)
           ) do
    quote do
      assert_receive {:socket_push, :text, message}, unquote(timeout)
      message = JSONSerializer.decode!(message, opcode: :text)
      assert unquote(payload) = message.payload["result"]
    end
  end

  @doc false
  def __connect__(endpoint, handler, params, connect_info) do
    map = %{
      endpoint: endpoint,
      options: [],
      params: __stringify__(params),
      connect_info: connect_info
    }

    case handler.connect(map) do
      {:ok, state} -> handler.init(state)
      error -> error
    end
  end

  @doc """
  Helper function for the `connection_init` message in the subscriptions-transport-ws
  protocol. Calls the `gql_connection_init(message, socket)` on the socket handler.

  """
  def gql_connection_init(socket, params) do
    push(socket, %OperationMessage{type: "connection_init", payload: params})
  end

  @doc """
  Helper function to push a GraphQL document to a socket.

  The only option that is used is `opts[:variables]` - all other options are
  ignored.

  When you push a query/mutation it will return with `{:ok, result, socket}`. For
  subscriptions it will return an `{:ok, socket}` tuple.

  ## Example of synchronous response
  ```elixir
  # Push query over socket and receive response
  push_doc(socket, "query {
      posts {
        id
        body
      }
    }", variables: %{limit: 10})
  {:ok, %{"data" => %{"posts" => [%{"body" => "body1", "id" => "aa"}]}}, _socket}
  ```

  ## Example of asynchronous response
  ```
  # Subscribe to subscription
  push_doc(socket, "subscription {
      postAdded{
        id
        body
        title
      }
  }", variables: %{})

  # The submitPost mutation triggers the postAdded subscription publication
  push_doc(socket, "mutation submitPost($title: String, $body: String){
    submitPost(title: $title, body: $body){
      id
      body
      title

    }
  }", variables: %{title: "test title", body: "test body"})

  assert_receive_subscription(%{
    "data" => %{
      "postAdded" => %{"body" => "test body", "id" => "1", "title" => "test title"}
    }
  })
  ```
  """
  @spec push_doc(socket :: Socket.t(), document :: String.t(), opts :: [{:variables, map}]) ::
          {:ok, Socket.t()} | {:ok, result :: map, Socket.t()}
  def push_doc(socket, document, opts \\ []) do
    case push(socket, %OperationMessage{
           id: opts[:id] || 1,
           type: "start",
           payload: %{query: document, variables: opts[:variables] || %{}}
         }) do
      {:ok, socket} ->
        {:ok, socket}

      {:reply, :ok, {:text, message}, socket} ->
        {:ok,
         socket.json_module.decode!(message) |> OperationMessage.from_map() |> Map.get(:payload),
         socket}
    end
  end

  # Lowlevel helper to push messages to the socket. Expects message map that can be converted to
  # an OperationMessage
  @doc false
  @spec push(socket :: Socket.t(), message :: map) ::
          {:ok, Socket.t()} | {:reply, :ok, {:text, String.t()}, Socket.t()}
  defp push(socket, message) do
    message = OperationMessage.as_json(message) |> socket.json_module.encode!
    socket.handler.handle_in({message, []}, socket)
  end

  @doc false
  def __stringify__(%{__struct__: _} = struct),
    do: struct

  def __stringify__(%{} = params),
    do: Enum.into(params, %{}, &stringify_kv/1)

  def __stringify__(other),
    do: other

  defp stringify_kv({k, v}),
    do: {to_string(k), __stringify__(v)}
end
