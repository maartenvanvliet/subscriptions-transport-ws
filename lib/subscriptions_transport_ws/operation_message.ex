defmodule SubscriptionsTransportWS.OperationMessage do
  @moduledoc """
  Struct to contain the protocol messages.

  See https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md
  for more details on their contents

  """

  @enforce_keys [:type]
  defstruct [:type, :id, :payload]

  @type t :: %__MODULE__{type: String.t(), id: String.t(), payload: any()}
  alias SubscriptionsTransportWS.Error

  @message_types ~w(
    complete
    connection_ack
    connection_error
    connection_init
    connection_terminate
    data
    error
    ka
    start
    stop
  )
  @doc """
  Prepare message for transport, removing any keys with nil values.

      iex> %OperationMessage{type: "complete", id: "1"} |> OperationMessage.as_json
      %{id: "1", type: "complete"}
  """
  def as_json(%__MODULE__{type: type} = message) when type in @message_types do
    message
    |> Map.from_struct()
    |> Enum.reject(&match?({_, nil}, &1))
    |> Map.new()
  end

  def as_json(%__MODULE__{type: type}) do
    raise Error, "Illegal `type` #{inspect(type)} in OperationMessage"
  end

  def as_json(_) do
    raise Error, "Missing `type` in OperationMessage"
  end

  @doc """
  Build `OperationMessage` from incoming map

      iex> %{"type" => "connection_init"} |> OperationMessage.from_map
      %OperationMessage{id: nil, type: "connection_init", payload: nil}
  """
  def from_map(%{"type" => type} = message) when type in @message_types do
    %__MODULE__{
      id: Map.get(message, "id"),
      payload: Map.get(message, "payload"),
      type: Map.get(message, "type")
    }
  end

  def from_map(%{"type" => type}) do
    raise Error, "Illegal `type` #{inspect(type)} in OperationMessage"
  end

  def from_map(_) do
    raise Error, "Missing `type` in OperationMessage"
  end
end
