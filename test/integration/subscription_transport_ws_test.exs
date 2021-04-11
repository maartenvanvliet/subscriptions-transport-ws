Code.require_file("../support/websocket_client.exs", __DIR__)
Code.require_file("../support/test_schema.exs", __DIR__)

defmodule SubscriptionsTransportWS.Integration.SocketTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias __MODULE__.Endpoint
  alias SubscriptionsTransportWS.OperationMessage
  alias SubscriptionsTransportWS.WebsocketClient

  @moduletag capture_log: true

  defmodule GraphqlSocket do
    use SubscriptionsTransportWS.Socket, schema: TestSchema, keep_alive: 10

    @impl true
    def connect(_params, socket) do
      {:ok, socket}
    end

    @impl true
    def gql_connection_init(message, socket) do
      case message.payload do
        %{"token" => "bogus"} ->
          {:error, "no user found"}

        %{"token" => "correct"} ->
          {:ok, socket |> Socket.assign_context(current_user: :user)}

        _ ->
          {:ok, socket}
      end
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :subscription_transport_ws
    use Absinthe.Phoenix.Endpoint

    socket("/ws", GraphqlSocket, websocket: [subprotocols: ["graphql-ws"]])
  end

  @port 5807
  Application.put_env(:subscription_transport_ws, Endpoint,
    https: false,
    http: [port: @port],
    debug_errors: false,
    server: true,
    pubsub_server: __MODULE__,
    secret_key_base: String.duplicate("a", 64)
  )

  setup_all do
    capture_log(fn -> start_supervised!(Endpoint) end)
    start_supervised!({Phoenix.PubSub, name: __MODULE__})

    start_supervised!(
      {Absinthe.Subscription, SubscriptionsTransportWS.Integration.SocketTest.Endpoint}
    )

    :ok
  end

  @path "ws://127.0.0.1:#{@port}/ws/websocket"
  @json_module Jason

  test "handles `connection_init` with valid credentials" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_event(socket, ~s({
      "type": "connection_init",
      "payload": {
        "token": "correct"
      }
    }))

    assert_receive %{"type" => "connection_ack"}
  end

  test "handles `connection_init` with invalid credentials" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_event(socket, ~s({
      "type": "connection_init",
      "payload": {
        "token": "bogus"
      }
    }))

    assert_receive %{"type" => "connection_error", "payload" => "no user found"}
  end

  test "handles query" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "  query {
          posts {
            id
            body
          }
        }",
        variables: %{}
      }
    })

    assert_receive %{
      "payload" => %{"data" => %{"posts" => [%{"body" => "body1", "id" => "aa"}]}},
      "type" => "data",
      "id" => 1
    }
  end

  test "receives published data on subscription" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "subscription {
          postAdded{
            id
            body
            title

          }
        }",
        variables: %{}
      }
    })

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 2,
      payload: %{
        query: "mutation submitPost($title: String, $body: String){
          submitPost(title: $title, body: $body){
            id
            body
            title

          }
        }",
        variables: %{title: "test title", body: "test body"}
      }
    })

    assert_receive %{
      "id" => 1,
      "payload" => %{
        "data" => %{
          "postAdded" => %{"body" => "test body", "id" => "1", "title" => "test title"}
        }
      },
      "type" => "data"
    }
  end

  test "receives complete after unsubscribing a subscription" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "subscription {
          postAdded{
            id
            body
            title

          }
        }",
        variables: %{}
      }
    })

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "stop",
      id: 1
    })

    assert_receive %{"id" => 1, "type" => "complete"}
  end

  test "terminates a connection subscription" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "subscription {
          postAdded{
            id
            body
            title

          }
        }",
        variables: %{}
      }
    })

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "connection_terminate"
    })
  end

  test "starts keep alive messages" do
    {:ok, socket} =
      WebsocketClient.start_link(
        self(),
        "ws://127.0.0.1:#{@port}/ws/websocket",
        @json_module
      )

    WebsocketClient.send_event(socket, ~s({
      "type": "connection_init",
      "payload": {
        "token": "correct"
      }
    }))
    assert_receive %{"type" => "connection_ack"}
    assert_receive %{"type" => "ka"}
  end

  test "continues to receive keep alive messages" do
    {:ok, socket} =
      WebsocketClient.start_link(
        self(),
        "ws://127.0.0.1:#{@port}/ws/websocket",
        @json_module
      )

    WebsocketClient.send_event(socket, ~s({
      "type": "connection_init",
      "payload": {
        "token": "correct"
      }
    }))
    assert_receive %{"type" => "connection_ack"}

    assert_receive %{"type" => "ka"}
    assert_receive %{"type" => "ka"}
  end

  test "returns error for invalid graphql document" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "subscription {
          postAdded{
            id
            doesNotExist
          }
        }",
        variables: %{}
      }
    })

    assert_receive %{
      "id" => 1,
      "payload" => %{
        "errors" => [
          %{
            "locations" => [%{"column" => 13, "line" => 4}],
            "message" => "Cannot query field \"doesNotExist\" on type \"Post\"."
          }
        ],
        "data" => %{}
      },
      "type" => "data"
    }
  end

  test "returns error for non-parseable variables subscription" do
    {:ok, socket} = WebsocketClient.start_link(self(), @path, @json_module)

    WebsocketClient.send_message(socket, %OperationMessage{
      type: "start",
      id: 1,
      payload: %{
        query: "subscription {
          postAdded{
            id
          }
        }",
        variables: ""
      }
    })

    assert_receive %{
      "id" => 1,
      "payload" => %{"errors" => "Could not parse variables"},
      "type" => "error"
    }
  end
end
