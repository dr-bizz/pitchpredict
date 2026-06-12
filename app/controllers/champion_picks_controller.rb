# Singular resource: one champion pick per user, created or changed from the
# dashboard until the tournament's opening kickoff.
class ChampionPicksController < ApplicationController
  # POST /champion_pick
  def create
    upsert_champion_pick
  end

  # PATCH /champion_pick
  def update
    upsert_champion_pick
  end

  private

  def champion_pick_params
    params.expect(champion_pick: [ :team_id ])
  end

  # NOTE: like predictions, the singular route carries no id, so create and
  # update share an upsert keyed on Current.user. A stale POST after a pick
  # already exists simply updates it. Both outcomes redirect back to the
  # dashboard; the model's tournament lock surfaces via flash[:alert].
  def upsert_champion_pick
    pick = Current.user.champion_pick || Current.user.build_champion_pick
    pick.assign_attributes(champion_pick_params)

    if pick.save
      redirect_to root_path, notice: "Champion pick saved: #{pick.team.name}."
    else
      redirect_to root_path, alert: pick.errors.full_messages.to_sentence
    end
  end
end
