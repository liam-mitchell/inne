factory :score do
  transient do
    r nil
    s nil
    u nil
  end

  sequence(:rank) { |n| n % 20 }
  sequence(:player) do |n|
    players = ['xela', 'jp27ace', 'High Priest o the Righteous Feed', 'golfkid', 'TOAST BUSTERS', 'Muzgrob', 'Maaz :D', 'overlordlork', 'Squadxzo', 'EddyMataGallos', 'Borlin', 'Jirka', 'natesly', 'Personman', 'Squidclaw', 'ibcamwhobu', 'muratcantonta', 'Mole', 'natesly']
    players[n % 20]
  end

  association :highscoreable, factory: :level
  player { create(:player, name: (u ? u : generate(:player))) }
  rank { r ? r : generate(:rank) }
  score { s ? s : (20 - rank) / 60 }
end
