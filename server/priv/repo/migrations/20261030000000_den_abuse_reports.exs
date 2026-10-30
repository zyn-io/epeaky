defmodule Den.Repo.Migrations.DenAbuseReports do
  use Ecto.Migration

  # Members' reports of a message to the den's moderators (Den.Reports): who
  # sent it and who reported it (device names), why, and its words only if
  # the reporter chose to include them.
  def change do
    create table(:abuse_reports, primary_key: false) do
      add :id, :string, primary_key: true
      add :room, :string, null: false
      add :msg, :string, null: false
      add :sender, :string, null: false
      add :reporter, :string, null: false
      add :reason, :string, null: false
      add :words, :text
      add :made_at, :utc_datetime, null: false
      add :done_at, :utc_datetime
      add :done_by, :string
    end

    create index(:abuse_reports, [:done_at, :made_at])
  end
end
