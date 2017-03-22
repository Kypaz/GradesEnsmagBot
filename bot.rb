require 'telegram/bot'
require 'open-uri'
require 'nokogiri'
require 'parseconfig'
require 'dalli'

config = ParseConfig.new('param.conf')

token = config['token']
$user_me = config['user']
$passwd_me = config['passwd']
$chat_me = config['chat']
$chat_grp = config['chat_group1']
$chat_class = config['chat_class']

options = { :namespace => "app", :compress => true }
$dc = Dalli::Client.new('localhost:11211', options)

def getGrades(user,passwd)
  urlGrades = 'https://intranet.ensimag.fr/Zenith2/ConsultNotes?uid='
  begin
    doc = Nokogiri::HTML(open(urlGrades+user, :http_basic_authentication=>[user, passwd]))
  rescue OpenURI::HTTPError => ex
    puts(ex)
    return nil
  end
  subjects = doc.css("tr td[1]")
  grades = doc.css("tr td[4]")
  coefs = doc.css("tr td[2]")
  sum = 0.0
  fullSum = 0.0;
  counter = 0
  result = ''
  subjects.each_with_index do |value,key|
    result += subjects[key].text + " - " + grades[key] + "\n";
    coef = coefs[key].text.to_f
    grade = grades[key].text.to_f
    if (coef != "0")
      sum = sum + coef*grade
      counter = counter + coef
    end
    fullSum = fullSum + grade
  end

  avg = sum/counter;
  result += "Avg = " + avg.to_s + " \n"
  if avg < 10
    result += "Rdv en Juillet \xE2\x9D\xA4"
  end
  if ($dc.get(user) == nil || $dc.get(user) != fullSum)
    $dc.set(user,fullSum)
    return result, false
  else
    return result, true
  end
end

Telegram::Bot::Client.run(token) do |bot|
  Thread.new do
    while true do
      result, bool = getGrades($user_me,$passwd_me)
      if (!bool)
        newGr = "NOUVELLES NOTES"
        result = newGr + " : \n" + result
        bot.api.send_message(chat_id: $chat_me, text: result)
        bot.api.send_message(chat_id: $chat_grp, text: result)
	bot.api.send_message(chat_id: $chat_class, text: newGr)
      else
	#bot.api.send_message(chat_id: $chat_class, text: "TEST")
      end
      sleep 60
    end
  end
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      case message.text
      when '/chat_id'
      	puts(message.chat.id)
      when '/rattrapage'
        puts(message.chat.id)
        grades,bool = getGrades($user_me,$passwd_me)
        if (grades != nil && message.from.username == "kypaz" )
          bot.api.send_message(chat_id: message.chat.id, text: grades)
        end
      end
    when Telegram::Bot::Types::InlineQuery
      if message.query != ""
        answers = []
        data = message.query.split(":")
        if (data[0] && data[1] != nil)
          grades,bool = getGrades(data[0],data[1])
        end
        if (grades != nil)
          rtn = "Nom : " + data[0] + "\n" + grades
          answers << Telegram::Bot::Types::InlineQueryResultArticle.new(
              id: 0,
              title: "RATTRAPAGES ?? (user:password)",
              input_message_content: Telegram::Bot::Types::InputTextMessageContent.new(message_text: rtn, parse_mode: "HTML"))
          puts bot.api.answer_inline_query(inline_query_id: message.id, results: answers)
      end
      end
    end
  end
end
