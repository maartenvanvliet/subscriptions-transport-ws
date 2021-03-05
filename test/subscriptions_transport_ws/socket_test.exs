Code.require_file("../support/test_schema.exs", __DIR__)

defmodule SubscriptionsTransportWS.Tests.SocketTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  import SubscriptionsTransportWS.SocketTest

  alias SubscriptionsTransportWS.OperationMessage

  @moduletag capture_log: true
  defmodule GraphqlSocket do
    use SubscriptionsTransportWS.Socket, schema: TestSchema, keep_alive: 1000

    @impl true
    def connect(params, socket) do
      send(self(), params)
      {:ok, socket}
    end

    @impl true
    def gql_connection_init(message, socket) do
      send(self(), message)
      {:ok, socket}
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :subscription_transport_ws
    use Absinthe.Phoenix.Endpoint

    socket("/ws", GraphqlSocket, websocket: [subprotocols: ["graphql-ws"]])
  end

  @endpoint Endpoint

  Application.put_env(:subscription_transport_ws, Endpoint, pubsub_server: __MODULE__)

  setup_all do
    capture_log(fn -> start_supervised!(Endpoint) end)
    start_supervised!({Phoenix.PubSub, name: __MODULE__})

    start_supervised!({Absinthe.Subscription, Endpoint})

    :ok
  end

  test "socket/2" do
    assert %SubscriptionsTransportWS.Socket{} = socket(GraphqlSocket, TestSchema)
  end

  test "connect" do
    {:ok, _socket} = connect(GraphqlSocket, %{auth: "token"})
    assert_receive %{"auth" => "token"}
  end

  test "connection_init" do
    {:ok, socket} = connect(GraphqlSocket, %{auth: "token"})

    {:reply, :ok, {:text, "{\"type\":\"connection_ack\"}"}, _socket} =
      gql_connection_init(socket, %{a: 1})

    assert_receive %OperationMessage{id: nil, payload: %{"a" => 1}, type: "connection_init"}
  end

  test "push_doc" do
    socket = socket(GraphqlSocket, TestSchema)

    {:ok, %{"data" => %{"posts" => [%{"body" => "body1", "id" => "aa"}]}}, _socket} =
      push_doc(socket, "query {
          posts {
            id
            body
          }
        }", variables: %{a: 1})
  end

  test "push_doc with subscription" do
    socket = socket(GraphqlSocket, TestSchema)

    {:ok, %SubscriptionsTransportWS.Socket{}} = push_doc(socket, "subscription {
          postAdded{
            id
            body
            title
          }
        }", variables: %{a: 1})

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
  end
end
