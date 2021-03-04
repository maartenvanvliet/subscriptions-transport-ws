defmodule SubscriptionsTransportWS.WebsocketClient do
  alias SubscriptionsTransportWS.OperationMessage

  @doc """
  Starts the WebSocket server for given ws URL. Received Socket.Message's
  are forwarded to the sender pid
  """
  def start_link(sender, url, json_module, headers \\ []) do
    :crypto.start()
    :ssl.start()

    :websocket_client.start_link(
      String.to_charlist(url),
      __MODULE__,
      [sender, json_module],
      extra_headers: headers
    )
  end

  def init([sender, json_module], _conn_state) do
    {:ok, %{sender: sender, json_module: json_module}}
  end

  def send_message(server_pid, operation_message) do
    send(server_pid, {:send, OperationMessage.as_json(operation_message) |> Jason.encode!()})
  end

  def send_event(server_pid, operation_message) do
    send(server_pid, {:send, operation_message})
  end

  def websocket_handle({:text, msg}, _conn_state, state) do
    send(state.sender, state.json_module.decode!(msg))

    {:ok, state}
  end

  def websocket_info({:send, msg}, _conn_state, state) do
    {:reply, {:text, msg}, state}
  end

  def websocket_info(:close, _conn_state, _state) do
    {:close, <<>>, "done"}
  end

  @doc """
  Closes the socket
  """
  def close(socket) do
    send(socket, :close)
  end
end
