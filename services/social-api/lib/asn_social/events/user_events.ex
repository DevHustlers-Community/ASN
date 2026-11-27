defmodule AsnSocial.Events.UserEvents do
  @moduledoc "Outbox envelope builders for Social user lifecycle events."

  alias AsnSocial.Accounts.User
  alias AsnSocial.UUIDv7

  @spec created(User.t(), keyword()) :: map()
  def created(user, opts \\ [])

  def created(%User{created_at: nil}, _opts) do
    raise ArgumentError, "created/2 requires a user with created_at set"
  end

  def created(%User{} = user, opts) do
    %{
      "event_id" => UUIDv7.generate(),
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => user.created_at,
      "aggregate_type" => "user",
      "aggregate_id" => user.id,
      "aggregate_version" => 1,
      "payload" => created_payload(user)
    }
    |> put_trace_id(opts)
  end

  defp created_payload(user) do
    %{
      "user_id" => user.id,
      "username" => user.username
    }
    |> put_unless_nil("display_name", user.display_name)
    |> put_unless_nil("avatar_key", user.avatar_key)
  end

  defp put_trace_id(envelope, opts) do
    case Keyword.get(opts, :trace_id) do
      trace_id when is_binary(trace_id) and trace_id != "" ->
        Map.put(envelope, "trace_id", trace_id)

      _other ->
        envelope
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
