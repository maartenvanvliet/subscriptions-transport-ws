# SubscriptionsTransportWS

## [![Hex pm](http://img.shields.io/hexpm/v/subscriptions_transport_ws.svg?style=flat)](https://hex.pm/packages/subscriptions_transport_ws) [![Hex Docs](https://img.shields.io/badge/hex-docs-9768d1.svg)](https://hexdocs.pm/subscriptions_transport_ws) [![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)![.github/workflows/elixir.yml](https://github.com/maartenvanvliet/subscriptions-transport-ws/workflows/.github/workflows/elixir.yml/badge.svg)
<!-- MDOC !-->

Implementation of the subscriptions-transport-ws graphql subscription protocol for Absinthe. Instead of using Absinthe subscriptions over Phoenix channels it exposes a websocket directly. This allows you to use
the Apollo and Urql Graphql clients without using a translation layer to Phoenix channels such as `@absinthe/socket`. 

Has been tested with Apollo iOS and Urql with subscriptions-transport-ws.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `subscriptions_transport_ws` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:subscriptions_transport_ws, "~> 1.0.0"}
  ]
end
```

## Usage

There are several steps to use this library. 

You need to have a working phoenix pubsub configured. Here is what the default looks like if you create a new phoenix project:
```elixir
config :my_app, MyAppWeb.Endpoint,
  # ... other config
  pubsub_server: MyApp.PubSub
```
In your application supervisor add a line AFTER your existing endpoint supervision line:

```elixir
[
  # other children ...
  MyAppWeb.Endpoint, # this line should already exist
  {Absinthe.Subscription, MyAppWeb.Endpoint}, # add this line
  # other children ...
]
```

Where MyAppWeb.Endpoint is the name of your application's phoenix endpoint.

Add a module in your app `lib/web/channels/absinthe_socket.ex`
```elixir
defmodule AbsintheSocket do
  # App.GraphqlSchema is your graphql schema
  use SubscriptionsTransportWS.Socket, schema: App.GraphqlSchema, keep_alive: 1000

  # Callback similar to default Phoenix UserSocket
  @impl true
  def connect(params, socket) do
    {:ok, socket}
  end

  # Callback to authenticate the user
  @impl true
  def gql_connection_init(message, socket) do
    {:ok, socket}
  end
end
```

In your MyAppWeb.Endpoint module add:
```elixir
  defmodule MyAppWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :my_app
    use Absinthe.Phoenix.Endpoint

    socket("/absinthe-ws", AbsintheSocket, websocket: [subprotocols: ["graphql-ws"]])
    # ...
  end
```

Now if you start your app you can connect to the socket on `ws://localhost:4000/absinthe-ws/websocket`

## Example with Apollo JS
```javascript
import {
  ApolloClient,
  InMemoryCache,
  ApolloProvider,
  useSubscription,
} from "@apollo/client";
import { split, HttpLink } from "@apollo/client";
import { getMainDefinition } from "@apollo/client/utilities";
import { WebSocketLink } from "@apollo/client/link/ws";

const wsLink = new WebSocketLink({
  uri: "ws://localhost:4000/absinthe-ws/websocket",
  options: {
    reconnect: true,
  },
});
const httpLink = new HttpLink({
  uri: "http://localhost:4000/api",
});

const splitLink = split(
  ({ query }) => {
    const definition = getMainDefinition(query);
    return (
      definition.kind === "OperationDefinition" &&
      definition.operation === "subscription"
    );
  },
  wsLink,
  httpLink
);

const client = new ApolloClient({
  uri: "http://localhost:4000/api",
  cache: new InMemoryCache(),
  link: splitLink,
});
```

See the [Apollo documentation](https://www.apollographql.com/docs/react/data/subscriptions/) for more information


## Example with Urql 
```javascript
import { SubscriptionClient } from "subscriptions-transport-ws";
import {
  useSubscription,
  Provider,
  defaultExchanges,
  subscriptionExchange,
} from "urql";

const subscriptionClient = new SubscriptionClient(
  "ws://localhost:4000/absinthe-ws/websocket",
  {
    reconnect: true,
  }
);

const client = new Client({
  url: "http://localhost:4000/api",
  exchanges: [
    subscriptionExchange({
      forwardSubscription(operation) {
        return subscriptionClient.request(operation);
      },
    }),
    ...defaultExchanges,
  ],
});
```
See the [Urql documentation](https://formidable.com/open-source/urql/docs/advanced/subscriptions/#setting-up-subscriptions-transport-ws) for more information.

## Example with Swift Apollo

```swift
import Apollo
import ApolloSQLite
import ApolloWebSocket
import Foundation
import Combine

class ApolloService {
    static let shared = ApolloService()
    static let url = Config.host.appendingPathComponent("api")
  
    private(set) lazy var client: ApolloClient = {

        let store = ApolloStore()
        
        let requestChainTransport = RequestChainNetworkTransport(
            interceptorProvider: DefaultInterceptorProvider(store: store),
            endpointURL: "https://localhost:4000/api"
        )
        
        // The Normal Apollo Web Socket Implementation which uses an Apollo adapter server side
        let wsUrl = "wss://localhost:4000/absinthe-ws/websocket"
        let wsRequest = URLRequest(url: wsUrl)
        let wsClient = WebSocket(request: wsRequest)
        let apolloWebSocketTransport =  WebSocketTransport(websocket: wsClient)

        let splitNetworkTransport = SplitNetworkTransport(
            uploadingNetworkTransport: requestChainTransport,
            webSocketNetworkTransport: apolloWebSocketTransport
          )

        // Remember to give the store you already created to the client so it
        // doesn't create one on its own
        let client =  ApolloClient(
            networkTransport: splitNetworkTransport,
            store: store
        )

        return client
    }()
}
```

Or see here https://www.apollographql.com/docs/ios/subscriptions/#subscriptions-and-authorization-tokens

<!-- MDOC !-->

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/subscriptions_transport_ws](https://hexdocs.pm/subscription_transport_ws).
