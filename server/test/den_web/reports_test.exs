defmodule DenWeb.ReportsTest do
  use DenWeb.ChannelCase, async: false
  import Ecto.Query
  alias Den.{Mod, Repo}

  @owner String.duplicate("0a", 32)
  @a String.duplicate("a1", 32)
  @b String.duplicate("b2", 32)
  @msg String.duplicate("c3", 8)

  defp lobby(key) do
    Den.Rooms.admit(key, DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second))
    {:ok, socket} = connect(DenWeb.UserSocket, %{"session" => Phoenix.Token.sign(DenWeb.Endpoint, "den", %{key: key})})
    {:ok, _, lobby} = subscribe_and_join(socket, DenWeb.LobbyChannel, "lobby")
    lobby
  end

  setup do
    Den.Rooms.seed()
    :ok = Mod.set_owner(@owner)
    :ok = Den.Rooms.seat("general", @a)
    :ok
  end

  test "a member reports a message; the owner reads it, marks it done; nobody else reads them" do
    a = lobby(@a)
    ref = push(a, "report_message", %{"room" => "general", "msg" => @msg, "sender" => @b, "reason" => "spam", "words" => "Buy my coin"})
    assert_reply ref, :ok, %{id: id}
    ref = push(a, "report_message", %{"room" => "general", "msg" => @msg, "sender" => @b, "reason" => "spam"})
    assert_reply ref, :ok, %{id: _}
    ref = push(a, "reports", %{})
    assert_reply ref, :error, %{reason: "You do not have permission to do that."}

    o = lobby(@owner)
    ref = push(o, "reports", %{})
    assert_reply ref, :ok, %{reports: [_, _] = rs}
    r = Enum.find(rs, &(&1.id == id))
    assert %{room: "general", msg: @msg, sender: @b, reporter: @a, reason: "spam", words: "Buy my coin", done_at: nil} = r
    assert is_integer(r.at)
    assert Enum.any?(rs, &is_nil(&1.words)), "the words only when the reporter includes them"
    ref = push(o, "report_done", %{"id" => id})
    assert_reply ref, :ok
    ref = push(o, "report_done", %{"id" => id})
    assert_reply ref, :error, _
    ref = push(o, "reports", %{})
    assert_reply ref, :ok, %{reports: [first, done]}
    assert is_nil(first.done_at) and done.id == id and done.done_by == @owner, "open ones first"
    assert Enum.any?(Mod.audit(), &(&1.action == "report done"))
  end

  test "a report names a real message and sender, with a reason; not one's own; 20 a day" do
    a = lobby(@a)
    bad = [
      {%{"msg" => "short"}, "That is not a message to report."},
      {%{"sender" => "m-not-a-key"}, "That is not a member's device."},
      {%{"sender" => @a}, "You cannot report your own message."},
      {%{"reason" => "  "}, "Say why, in up to 300 characters."},
      {%{"room" => "nowhere"}, "There is no such channel."},
      {%{"room" => "news"}, "You can report messages only in rooms you are in."}
    ]

    for {change, said} <- bad do
      ref = push(a, "report_message", Map.merge(%{"room" => "general", "msg" => @msg, "sender" => @b, "reason" => "spam"}, change))
      assert_reply ref, :error, %{reason: ^said}
    end

    # The day's 20 (straight to Den.Reports: the channel also slows a burst).
    for _ <- 1..20, do: {:ok, _} = Den.Reports.file(@a, %{"room" => "general", "msg" => @msg, "sender" => @b, "reason" => "spam"})

    ref = push(a, "report_message", %{"room" => "general", "msg" => @msg, "sender" => @b, "reason" => "spam"})
    assert_reply ref, :error, %{reason: "That is enough reports for today. Try again tomorrow."}
  end

  test "a device deletes its account: its day ends, its push addresses and invitations go, and it is sent away" do
    Repo.insert_all("push_subs", [%{endpoint: "https://web.push.apple.com/x", key: @a, p256dh: "p", auth: "a", mode: "all", made_at: Den.Rooms.now()}])
    @endpoint.subscribe("device:" <> @a)
    a = lobby(@a)
    ref = push(a, "leave_den", %{})
    assert_reply ref, :ok
    assert DateTime.compare(Den.Rooms.device_until(@a), DateTime.utc_now()) == :lt
    assert Repo.all(from s in "push_subs", where: s.key == ^@a, select: s.endpoint) == []
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 1000
  end
end
