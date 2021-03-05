defmodule SubscriptionsTransportWS.Socket do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  require Logger

  alias SubscriptionsTransportWS.OperationMessage
  alias __MODULE__

  @typedoc """

  When using this module there are several options available

   * `json_module` - defaults to Jason
   * `schema` - refers to the Absinthe schema (required)
   * `pipeline` - refers to the Absinthe pipeline to use, defaults to `{SubscriptionsTransportWS.Socket, :default_pipeline}`
   * `keep_alive` period in ms to send keep alive messages over the socket, defaults to 10000

  ## Example

  use SubscriptionsTransportWS.Socket, schema: App.GraphqlSchema, keep_alive: 1000

  """
  defstruct [
    :handler,
    :pubsub_server,
    :endpoint,
    :json_module,
    keep_alive: 10000,
    serializer: Phoenix.Socket.V2.JSONSerializer,
    operations: %{},
    assigns: %{}
  ]

  @type t :: %Socket{
          assigns: map,
          endpoint: atom,
          handler: atom,
          pubsub_server: atom,
          serializer: atom,
          json_module: atom,
          operations: map,
          keep_alive: integer | nil
        }

  @initial_keep_alive_wait 1

  @doc """
  Receives the socket params and authenticates the connection.

  ## Socket params and assigns

  Socket params are passed from the client and can
  be used to verify and authenticate a user. After
  verification, you can put default assigns into
  the socket that will be set for all channels, ie

      {:ok, assign(socket, :user_id, verified_user_id)}

  To deny connection, return `:error`.

  See `Phoenix.Token` documentation for examples in
  performing token verification on connect.
  """
  @callback connect(params :: map, Socket.t()) :: {:ok, Socket.t()} | :error
  @callback connect(params :: map, Socket.t(), connect_info :: map) :: {:ok, Socket.t()} | :error

  @doc """
  Callback for the `connection_init` message.
  The client sends this message after plain websocket connection to start
  the communication with the server.

  In the `subscriptions-transport-ws` protocol this is usually used to
  set the user on the socket.

  Should return `{:ok, socket}` on success, and `{:error, payload}` to deny.

  Receives the a map of `connection_params`, see

    * connectionParams in [Apollo javascript client](https://github.com/apollographql/subscriptions-transport-ws/blob/06b8eb81ba2b6946af4faf0ae6369767b31a2cc9/src/client.ts#L62)
    * connectingPayload in [Apollo iOS client](https://github.com/apollographql/apollo-ios/blob/ca023e5854b5b78529eafe9006c6ce1e3c2db539/docs/source/api/ApolloWebSocket/classes/WebSocketTransport.md)

  or similar in other clients.
  """
  @callback gql_connection_init(connection_params :: map, Socket.t()) ::
              {:ok, Socket.t()} | {:error, any}

  @optional_callbacks connect: 2, connect: 3

  defmacro __using__(opts) do
    quote do
      import SubscriptionsTransportWS.Socket

      alias SubscriptionsTransportWS.Socket

      @phoenix_socket_options unquote(opts)

      @behaviour Phoenix.Socket.Transport
      @behaviour SubscriptionsTransportWS.Socket

      @doc false
      @impl true
      def child_spec(opts) do
        Socket.__child_spec__(
          __MODULE__,
          opts,
          @phoenix_socket_options
        )
      end

      @doc false
      @impl true
      def connect(state),
        do:
          Socket.__connect__(
            __MODULE__,
            state,
            @phoenix_socket_options
          )

      @doc false
      @impl true
      def init(socket), do: Socket.__init__(socket)

      @doc false
      @impl true
      def handle_in(message, socket),
        do: Socket.__in__(message, socket)

      @doc false
      @impl true
      def handle_info(message, socket),
        do: Socket.__info__(message, socket)

      @doc false
      @impl true
      def terminate(reason, socket),
        do: Socket.__terminate__(reason, socket)
    end
  end

  def __child_spec__(_module, _opts, _socket_options) do
    # Nothing to do here, so noop.
    %{id: Task, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
  end

  def __connect__(module, socket, socket_options) do
    json_module = Keyword.get(socket_options, :json_module, Jason)
    schema = Keyword.get(socket_options, :schema)
    pipeline = Keyword.get(socket_options, :pipeline)
    keep_alive = Keyword.get(socket_options, :keep_alive)

    case user_connect(
           module,
           socket.endpoint,
           socket.params,
           socket.connect_info,
           json_module,
           keep_alive
         ) do
      {:ok, socket} ->
        absinthe_config = Map.get(socket.assigns, :absinthe, %{})

        opts =
          absinthe_config
          |> Map.get(:opts, [])
          |> Keyword.update(:context, %{pubsub: socket.endpoint}, fn context ->
            Map.put_new(context, :pubsub, socket.endpoint)
          end)

        absinthe_config =
          put_in(absinthe_config[:opts], opts)
          |> Map.update(:schema, schema, & &1)

        absinthe_config =
          Map.put(absinthe_config, :pipeline, pipeline || {__MODULE__, :default_pipeline})

        socket = socket |> assign(:absinthe, absinthe_config)

        {:ok, socket}

      :error ->
        :error
    end
  end

  defp user_connect(handler, endpoint, params, connect_info, json_module, keep_alive) do
    if pubsub_server = endpoint.config(:pubsub_server) do
      socket = %SubscriptionsTransportWS.Socket{
        handler: handler,
        endpoint: endpoint,
        pubsub_server: pubsub_server,
        json_module: json_module,
        keep_alive: keep_alive
      }

      connect_result =
        if function_exported?(handler, :connect, 3) do
          handler.connect(params, socket, connect_info)
        else
          handler.connect(params, socket)
        end

      connect_result
    else
      Logger.error("""
      The :pubsub_server was not configured for endpoint #{inspect(endpoint)}.

      Make sure to start a PubSub proccess in your application supervision tree:
          {Phoenix.PubSub, [name: YOURAPP.PubSub, adapter: Phoenix.PubSub.PG2]}

      And then list it your endpoint config:
          pubsub_server: YOURAPP.PubSub
      """)

      :error
    end
  end

  @doc """
  Adds key value pairs to socket assigns.
  A single key value pair may be passed, a keyword list or map
  of assigns may be provided to be merged into existing socket
  assigns.

  ## Examples

      iex> assign(socket, :name, "Elixir")
      iex> assign(socket, name: "Elixir", logo: "💧")

  """
  def assign(socket, key, value) do
    assign(socket, [{key, value}])
  end

  def assign(socket, attrs) when is_map(attrs) or is_list(attrs) do
    %{socket | assigns: Map.merge(socket.assigns, Map.new(attrs))}
  end

  @doc """
  Sets the options for a given GraphQL document execution.

  ## Examples

      iex> SubscriptionsTransportWS.Socket.put_options(socket, context: %{current_user: user})
      %SubscriptionsTransportWS.Socket{}
  """
  def put_options(socket, opts) do
    absinthe_assigns =
      socket.assigns
      |> Map.get(:absinthe, %{})

    absinthe_assigns =
      absinthe_assigns
      |> Map.put(:opts, Keyword.merge(Map.get(absinthe_assigns, :opts, []), opts))

    assign(socket, :absinthe, absinthe_assigns)
  end

  @doc """
  Adds key-value pairs into Absinthe context.

  ## Examples

      iex> Socket.assign_context(socket, current_user: user)
      %Socket{}
  """
  def assign_context(%Socket{assigns: %{absinthe: absinthe}} = socket, context) do
    context =
      absinthe
      |> Map.get(:opts, [])
      |> Keyword.get(:context, %{})
      |> Map.merge(Map.new(context))

    put_options(socket, context: context)
  end

  def assign_context(socket, assigns) do
    put_options(socket, context: Map.new(assigns))
  end

  @doc """
  Same as `assign_context/2` except one key-value pair is assigned.
  """
  def assign_context(socket, key, value) do
    assign_context(socket, [{key, value}])
  end

  @doc false
  def __init__(state) do
    {:ok, state}
  end

  @doc false
  def __in__({text, _opts}, socket) do
    message = socket.json_module.decode!(text)

    message = OperationMessage.from_map(message)

    handle_message(socket, message)
  end

  @doc false
  def __info__(:keep_alive, socket) do
    reply =
      %OperationMessage{type: "ka"}
      |> OperationMessage.as_json()
      |> socket.json_module.encode!

    Process.send_after(self(), :keep_alive, socket.keep_alive)
    {:reply, :ok, {:text, reply}, socket}
  end

  def __info__({:socket_push, :text, message}, socket) do
    message = socket.serializer.decode!(message, opcode: :text)

    id = Map.get(socket.operations, message.topic)

    reply =
      %OperationMessage{type: "data", id: id, payload: %{data: message.payload["result"]["data"]}}
      |> OperationMessage.as_json()
      |> socket.json_module.encode!

    {:reply, :ok, {:text, reply}, socket}
  end

  @doc false
  def __terminate__(_reason, _state) do
    :ok
  end

  @doc """
  Default pipeline to use for Absinthe graphql document execution
  """
  def default_pipeline(schema, options) do
    schema
    |> Absinthe.Pipeline.for_document(options)
  end

  defp handle_message(socket, %{type: "connection_init"} = message) do
    case socket.handler.gql_connection_init(message, socket) do
      {:ok, socket} ->
        if socket.keep_alive do
          Process.send_after(self(), :keep_alive, @initial_keep_alive_wait)
        end

        reply =
          %OperationMessage{type: "connection_ack"}
          |> OperationMessage.as_json()
          |> socket.json_module.encode!

        {:reply, :ok, {:text, reply}, socket}

      {:error, payload} ->
        reply =
          %OperationMessage{type: "connection_error", payload: payload}
          |> OperationMessage.as_json()
          |> socket.json_module.encode!

        {:reply, :ok, {:text, reply}, socket}
    end
  end

  defp handle_message(socket, %{type: "stop", id: id}) do
    doc_id =
      Enum.find_value(socket.operations, fn {key, op_id} ->
        if id == op_id, do: key
      end)

    reply =
      %OperationMessage{type: "complete", id: id}
      |> OperationMessage.as_json()
      |> socket.json_module.encode!

    case doc_id do
      nil ->
        {:reply, :ok, {:text, reply}, socket}

      doc_id ->
        pubsub =
          socket.assigns
          |> Map.get(:absinthe, %{})
          |> Map.get(:opts, [])
          |> Keyword.get(:context, %{})
          |> Map.get(:pubsub, socket.endpoint)

        Phoenix.PubSub.unsubscribe(socket.pubsub_server, doc_id)
        Absinthe.Subscription.unsubscribe(pubsub, doc_id)
        socket = %{socket | operations: Map.delete(socket.operations, doc_id)}

        {:reply, :ok, {:text, reply}, socket}
    end
  end

  defp handle_message(socket, %{type: "start", payload: payload, id: id}) do
    config = socket.assigns[:absinthe]

    case extract_variables(payload) do
      variables when is_map(variables) ->
        opts = Keyword.put(config.opts, :variables, variables)
        query = Map.get(payload, "query", "")

        Absinthe.Logger.log_run(:debug, {query, config.schema, [], opts})

        {reply, socket} = run_doc(socket, query, config, opts, id)

        Logger.debug(fn ->
          """
          -- Absinthe Phoenix Reply --
          #{inspect(reply)}
          ----------------------------
          """
        end)

        if reply != :noreply do
          case reply do
            {:ok, operation_message} ->
              {:reply, :ok,
               {:text, OperationMessage.as_json(operation_message) |> socket.json_module.encode!},
               socket}
          end
        else
          {:ok, socket}
        end

      _ ->
        reply = %OperationMessage{
          type: "error",
          id: id,
          payload: %{errors: "Could not parse variables"}
        }

        {:reply, :ok, {:text, OperationMessage.as_json(reply) |> socket.json_module.encode!},
         socket}
    end
  end

  defp handle_message(socket, %{type: "connection_terminate"}) do
    Enum.each(socket.operations, fn {doc_id, _} ->
      pubsub =
        socket.assigns
        |> Map.get(:absinthe, %{})
        |> Map.get(:opts, [])
        |> Keyword.get(:context, %{})
        |> Map.get(:pubsub, socket.endpoint)

      Phoenix.PubSub.unsubscribe(socket.pubsub_server, doc_id)
      Absinthe.Subscription.unsubscribe(pubsub, doc_id)
    end)

    socket = %{socket | operations: %{}}
    {:ok, socket}
  end

  defp extract_variables(payload) do
    case Map.get(payload, "variables", %{}) do
      nil -> %{}
      map -> map
    end
  end

  defp run_doc(socket, query, config, opts, id) do
    case run(query, config[:schema], config[:pipeline], opts) do
      {:ok, %{"subscribed" => topic}, context} ->
        :ok =
          Phoenix.PubSub.subscribe(
            socket.pubsub_server,
            topic,
            metadata: {:fastlane, self(), socket.serializer, []}
          )

        socket = put_options(socket, context: context)

        socket = %{socket | operations: Map.put(socket.operations, topic, id)}

        {:noreply, socket}

      {:ok, %{data: data}, context} ->
        socket = put_options(socket, context: context)

        reply = %OperationMessage{
          type: "data",
          id: id,
          payload: %{data: data}
        }

        {{:ok, reply}, socket}

      {:ok, %{errors: errors}, context} ->
        socket = put_options(socket, context: context)

        reply = %OperationMessage{
          type: "data",
          id: id,
          payload: %{data: %{}, errors: errors}
        }

        {{:ok, reply}, socket}

      {:error, error} ->
        reply = %OperationMessage{
          type: "error",
          id: id,
          payload: %{errors: error}
        }

        {{:ok, reply}, socket}
    end
  end

  defp run(document, schema, pipeline, options) do
    {module, fun} = pipeline

    case Absinthe.Pipeline.run(document, apply(module, fun, [schema, options])) do
      {:ok, %{result: result, execution: res}, _phases} ->
        {:ok, result, res.context}

      {:error, msg, _phases} ->
        {:error, msg}
    end
  end
end
