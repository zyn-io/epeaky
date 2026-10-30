defmodule Den.Reports do
  @moduledoc """
  A member reports a message to the den's moderators: the room, the
  message's id, its sender's device, a reason, and the message's words only
  if the reporter includes them (the den cannot read them otherwise). The
  den checks that the reporter is in that room; it cannot check the words
  or the sender (both are sealed), so a moderator's page checks the words
  against its own copy of the message. The
  owner and those with Manage messages read the reports and mark them done;
  what they do about one is the den's moderation (delete, timeout, kick, ban).
  A device files at most #{20} a day.
  """
  import Ecto.Query
  alias Den.{Repo, Rooms}

  @per_day 20
  @reason_max 300
  @words_max 4000
  @keep 1000

  @doc "A report from `reporter`."
  def file(reporter, %{"room" => room, "msg" => msg, "sender" => sender, "reason" => reason} = p)
      when is_binary(room) and is_binary(msg) and is_binary(sender) and is_binary(reason) do
    words = p["words"]
    reason = String.trim(reason)

    with true <- Regex.match?(~r/\A[0-9a-f]{16,32}\z/, msg) || {:error, :report},
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, sender) || {:error, :key},
         true <- sender != reporter || {:error, :self},
         true <- reason != "" and String.length(reason) <= @reason_max || {:error, :reason},
         true <- is_nil(words) or (is_binary(words) and String.length(words) <= @words_max) || {:error, :words},
         %{} <- Rooms.get(room) || {:error, :room},
         true <- reporter in Rooms.present(room) || {:error, :not_in_room},
         :ok <- Rooms.quota(reporter, "report", @per_day) do
      id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      Repo.insert_all("abuse_reports", [%{id: id, room: room, msg: msg, sender: sender, reporter: reporter, reason: reason, words: words, made_at: Rooms.now()}])
      trim()
      {:ok, id}
    end
  end

  def file(_, _), do: {:error, :report}

  @doc "The reports, open ones first, newest first."
  def list(n \\ 200) do
    Repo.all(
      from r in "abuse_reports",
        order_by: [asc: not is_nil(r.done_at), desc: r.made_at],
        limit: ^n,
        select: %{id: r.id, room: r.room, msg: r.msg, sender: r.sender, reporter: r.reporter, reason: r.reason, words: r.words, at: type(r.made_at, :utc_datetime), done_at: type(r.done_at, :utc_datetime), done_by: r.done_by}
    )
  end

  @doc "How many are open."
  def open, do: Repo.one(from r in "abuse_reports", where: is_nil(r.done_at), select: count())

  @doc "A moderator marks one done."
  def done(actor, id) when is_binary(id) do
    case Repo.update_all(from(r in "abuse_reports", where: r.id == ^id and is_nil(r.done_at)), set: [done_at: Rooms.now(), done_by: actor]) do
      {1, _} -> :ok
      _ -> {:error, :report}
    end
  end

  def done(_, _), do: {:error, :report}

  @doc "Who may read them: the owner, and anyone with Manage messages."
  def reader?(key), do: Den.Mod.can?(key, "manage_messages")

  # The newest @keep are kept.
  defp trim do
    old = Repo.all(from r in "abuse_reports", order_by: [desc: r.made_at], limit: -1, offset: @keep, select: r.id)
    if old != [], do: Repo.delete_all(from r in "abuse_reports", where: r.id in ^old)
    :ok
  end
end
