defmodule Pinchflat.Repo.Migrations.AddPlaybackPositionToMediaItems do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      add :playback_position_seconds, :integer, default: 0
    end
  end
end
