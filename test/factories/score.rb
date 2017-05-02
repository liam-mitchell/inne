FactoryGirl.define do
  factory :score do
    association :highscoreable, factory: :level
    association :player, factory: :player

    rank 0
    tied_rank { rank }
    score 90.000

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
