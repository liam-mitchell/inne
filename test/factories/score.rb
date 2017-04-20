FactoryGirl.define do
  factory :score do
    # transient do
    #   r nil
    #   s nil
    #   u nil
    # end

    # sequence(:rank) { |n| n % 20 }
    # sequence(:player) do |n|
    #   players = ['xela', 'jp27ace', 'High Priest o the Righteous Feed', 'golfkid', 'TOAST BUSTERS', 'Muzgrob', 'Maaz :D', 'overlordlork', 'Squadxzo', 'EddyMataGallos', 'Borlin', 'Jirka', 'natesly', 'Personman', 'Squidclaw', 'ibcamwhobu', 'muratcantonta', 'Mole', 'natesly']
    #   players[n % 20]
    # end

    association :highscoreable, factory: :level
    rank 0
    score 90.000
    player

    factory :xela do
      player { create(:player, name: 'xela') }
    end

    factory :jp do
      player { create(:player, name: 'jp27ace') }
    end

    factory :borlin do
      player { create(:player, name: 'Borlin') }
    end

    factory :eddy do
      player { create(:player, name: 'EddyMataGallos') }
    end

    factory :golf do
      player { create(:player, name: 'golfkid') }
    end
  end
end
