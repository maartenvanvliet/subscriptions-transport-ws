defmodule TestSchema do
  use Absinthe.Schema

  object :post do
    field(:id, :id)
    field(:title, :string)
    field(:body, :string)
  end

  query do
    @desc "Get all posts"
    field :posts, list_of(:post) do
      resolve(&list_posts/3)
    end
  end

  mutation do
    field :submit_post, :post do
      arg(:title, non_null(:string))
      arg(:body, non_null(:string))

      resolve(&submit_post/3)
    end
  end

  subscription do
    field :post_added, :post do
      config(fn _, _ ->
        {:ok, topic: "*"}
      end)

      trigger(:submit_post,
        topic: fn _ ->
          "*"
        end
      )
    end
  end

  def submit_post(_parent, args, _resolution) do
    {:ok,
     %{
       id: 1,
       title: args.title,
       body: args.body
     }}
  end

  def list_posts(_parent, _args, _resolution) do
    {:ok,
     [
       %{
         id: "aa",
         title: "title1",
         body: "body1"
       }
     ]}
  end
end
