require 'json'
require 'logger'
require 'net/http'
require 'uri'
require 'line/bot' 
require 'open-uri'
require 'kconv'
require 'rexml/document'

def lambda_handler(event:, context:)
    logger = Logger.new(STDOUT)
    log_formatter = proc { |severity, timestamp, _, msg|
        JSON.dump({time: timestamp, level: severity, message: msg})
    }
    logger.formatter = log_formatter
    
    logger.info event
    signature = event["headers"]["x-line-signature"]
    lambda_event_body = JSON.parse(event['body'])
    body = lambda_event_body.to_json
    unless client.validate_signature(body, signature)
      return  { statusCode: 400 }
    end
    
    
    events =  lambda_event_body["events"]
    logger.info events
    events.each { |event|
        case event["type"]
        #メッセージが送信された場合の対応（機能①）
        when "message"
            case event["message"]["type"]
            # ユーザーからテキスト形式のメッセージが送られて来た場合
            when "text"
                #event["message"]['text']：ユーザーから送られたメッセージ
                input = event["message"]['text'] 
                message = search_and_create_message(input)
            #テキスト以外（画像等）のメッセージが送られた場合
            else
                message = {
                    type: 'text',
                    text: "テキスト以外はわからないよ〜(；；)"
                }
            end
            
            client.reply_message(event['replyToken'], message)
        else
            message = {
                type: 'text',
                text: "欲しいものを教えてね！"
            }
            client.reply_message(event['replyToken'], message)
        end
    }
    return { statusCode: 200 }
end

private

    def client
        @client ||= Line::Bot::Client.new { |config|
          config.channel_id = ENV["LINE_CHANNEL_ID"]
          config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
          config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
        }
    end

    def search_and_create_message(input)
        RakutenWebService.configure do |client|
            # (必須) アプリケーションID
            client.application_id = ENV["RWS_APPLICATION_ID"]
            # (任意) 楽天アフィリエイトID
            client.affiliate_id = ENV["RWS_AFFILIATE_ID"]
        end

        res = RakutenWebService::Ichiba::Item.search(keyword: input, hits: 3, imageFlag: 1)
        items = []
        items = res.map{|item| item}
        make_reply_contents(items)
    end

    def make_reply_contents(items)
        {
            "type": 'flex',
            #Push通知時のメッセージ
            "altText": 'This is a Flex Message',
            "contents":
            {
                "type": 'carousel',
                "contents": [
                make_part(items[0]),
                make_part(items[1]),
                make_part(items[2])
                ]
            }
        }
    end

    def make_part(item)
        title = item['itemName']
        price = item['itemPrice'].to_s + '円'
        url = item['itemUrl']
        image = item['mediumImageUrls'].first
        {
          "type": "bubble",
          "hero": {
            "type": "image",
            "size": "full",
            "aspectRatio": "20:13",
            "aspectMode": "cover",
            "url": image
          },
          "body":
          {
            "type": "box",
            "layout": "vertical",
            "spacing": "sm",
            "contents": [
              {
                "type": "text",
                "text": title,
                "wrap": true,
                "weight": "bold",
                "size": "lg"
              },
              {
                "type": "box",
                "layout": "baseline",
                "contents": [
                  {
                    "type": "text",
                    "text": price,
                    "wrap": true,
                    "weight": "bold",
                    "flex": 0
                  }
                ]
              }
            ]
          },
          "footer": {
            "type": "box",
            "layout": "vertical",
            "spacing": "sm",
            "contents": [
              {
                "type": "button",
                "style": "primary",
                "action": {
                  "type": "uri",
                  "label": "楽天市場商品ページへ",
                  "uri": url
                }
              }
            ]
          }
        }
    end