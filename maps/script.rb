require 'net/http'

$done = [{exists: true, done: false}] * 18

def url(page)
  URI("https://dojo.nplusplus.ninja/prod/steam/query_levels?steam_id=76561198031272062&steam_auth=&qt=10&mode=0&page=#{page}")
end

def get(page)
  print("Trying page " + page.to_s + "... ")
  response = Net::HTTP.get(url(page))
  if response.size == 48
    $done[page][:exists] = false
    $done[page][:done] = false
    print("doesn't exist.")
    return 0
  end  
  if response == '-1337'
    print("failed.")
    return 0
  end
  if response.include?("502 Bad Gateway")
    print("failed.")
    return 0
  end
  $done[page][:exists] = true
  $done[page][:done] = true
  print("done.")
  return response
end


$done.each_with_index{ |page, i|
  file = get(i)
  if file != 0 then File.write(i.to_s, file) end
}
