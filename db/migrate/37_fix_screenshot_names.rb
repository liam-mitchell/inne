class FixScreenshotNames < ActiveRecord::Migration[5.1]
  def change
    f = "screenshots/"
    (20..23).to_a.product(("A".."E").to_a).map{ |n| n.reverse.join("-") + ".jpg" }.each_with_index{ |name, i|
      print("Renaming screenshot #{2 * i} / 40...".ljust(80, " ") + "\r")
      File.rename(f + "SS-"  + name, f + "SS-X-#{"%02d" % i}.jpg")  rescue nil
      File.rename(f + "SS2-" + name, f + "SS2-X-#{"%02d" % i}.jpg") rescue nil
    }
  end
end
