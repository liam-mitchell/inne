# Internally we use the same tabs as Solo mode because, in essence, they're the same
# However, it makes no sense to use the same names, since the evo
def tab(prefix)
  {
    'SI' => :SI,
    'S' => :S,
    'SL' => :SL,
    'SU' => :SU
  }[prefix]
end

def ids(tab, offset, n)
  ret = (0..n - 1).to_a.map{ |s|
    tab + "-" + s.to_s.rjust(2,"0")
  }.each_with_index.map{ |l, i| [offset + i, l] }.to_h
end

class CreateStories < ActiveRecord::Migration[5.1]
  def change
    create_table :stories do |t|
      t.string :name
      t.boolean :completed
      t.integer :tab, index: true
    end

    # Seed stories
    ActiveRecord::Base.transaction do
      [['SI', 0, 5], ['S', 24, 20], ['SL', 48, 20], ['SU', 96, 20]].each{ |s|
        ids(s[0],s[1],s[2]).each{ |story|
          Story.find_or_create_by(id: story[0]).update(
            #completed: false, # commented because we use nil instead
            name: story[1],
            tab: tab(story[1].split('-')[0])
          )
        }
      }
      GlobalProperty.create(key: 'next_story_update', value: (Time.now + 86400).to_s)
      #GlobalProperty.create(key: 'current_story', value: 'S-15')
      #GlobalProperty.create(key: 'saved_story_scores', value: [])
    end
  end
end
