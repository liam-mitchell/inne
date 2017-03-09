require 'discordrb'
require 'json'
require 'net/http'

API_BASE = 'https://discordapp.com/api'

bot = Discordrb::Bot.new token: 'Mjg5MTQxNzc2MjA2MjY2MzY5.C6IDyQ.1B1a2x_k7CF4UfaGWvhbGFVqdqM', client_id: 289141776206266369

puts "the bot's URL is #{bot.invite_url}"

bot.message(content: 'Ping!') do |event|
  event.respond 'Pong!'
end

bot.mention do |event|
  event.respond 'Hi! I\'m checking the channel for old levels and episodes of the day...'
  event.respond event.content

  uri = URI("#{API_BASE}/channels/#{event.channel.id}/messages")
  messages = JSON.parse(Net::HTTP.get(uri))
  event.respond "Messages found: #{messages}"
end

bot.run
