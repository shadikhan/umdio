require 'open-uri'
require 'nokogiri'
require 'uri'
require 'pry'
require 'mongo'
include Mongo
#
##set up mongo database - code from ruby mongo driver tutorial
host = ENV['MONGO_RUBY_DRIVER_HOST'] || 'localhost'
port = ENV['MONGO_RUBY_DRIVER_PORT'] || MongoClient::DEFAULT_PORT
#
##announce connection and connect
#puts "Connecting to #{host}:#{port}"
db = MongoClient.new(host, port, pool_size: 2, pool_timeout: 2).db('umdevents')

year = Time.now.strftime("%Y");
month = Time.now.strftime("%m");
ids = []
events = []
coll = db.collection('events')
bulk = coll.initialize_unordered_bulk_op

def parse(url, loc, cat)
	doc2 = Nokogiri::HTML(open(url))
	name = doc2.css(".eventTitle").text #title
	id = doc2.css(".eventLink").text #id num
	loc = URI.unescape(loc) #unencode the html
	location = loc.gsub('+', ' ') 
	dates = doc2.css(".eventDetails .eventField").text
	dates = exs.split("-")
	startDate = DateTime.parse(dates[0])
	endDate = DateTime.parse(dates[1])
	description = doc2.css(".eventDescription").text
	moreDescrip = doc2.css(".eventDescription ~ p:not(.eventWebsite):not(.eventContact)").text
	for d in moreDescrip
		description += d
	end
	
	events << {
		id: id,
		title:	doc2.css(".eventTitle").text,  
		category: cat,
		location: location,
		startDate: startDate,
		endDate: endDate,
		description: description,
		ticketInfo: doc2.css("p.eventTicket").text,
		website: doc2.css(".eventWebsite a").text,
		contact: doc2.css(".eventContactInfo").text
	}

end 

def fParse(tmp)
	base_url2 = "http://www.umd.edu/fyi/index.cfm?id="
	if (/fyi\.(\d+)/) === tmp
    		id = tmp.match(/fyi\.(\d+)/)[1]  
		if !$ids.include?(id) #avoid printing multiple ids 
			$ids << id
			#if (/\"location\\\";s:\d+:\\\"([A-Za-z0-9\+\%]+)\\\"/) === tmp #has designated location
			#
			place = tmp.match(/\"location\\\";s:\d+:\\\"([A-Za-z0-9\+\%]+)\\\"/)[1]
		else 
				place = ' '
		end
		if (/\"categories\\\";s:\d+:\\\"([A-Za-z0-9\+ \%]+)\\\"/) === tmp #has designated category
			cat  = tmp.match(/\"categories\\\";s:\d+:\\\"([A-Za-z0-9\+ \%]+)\\\"/)[1]
		else 
			cat = ' '
		end
		#category and location are easier to get from  javascript
		parse(base_url2+id, place, cat)
	end
end

m = month.to_i
monthThr = []
for i in 5..5
    	month_num = i
    	if month_num < 10
        	month_num = '0' + month_num.to_s;
    	end 
    	base_url = "https://www.umd.edu/fyi/calendar/month.php?cpath=&cal=Academic%2BCalendar%2B2013-2014%2CArt%2BExhibition%2CAthletics%2CColloquium%2CCommunity%2BService%2CConcert%2CConference%2CDance%2BPerformance%2CDiversity%2CForum%2CHealth%2CLecture%2CMCE%2CMeeting%2CMovieFilmVideo%2COther%2CRecreation%2CSeminar%2CSpecial%2BEvent%2CTheatre%2BPerformance%2CTraining&getdate=" + year + month_num + "01&form_action=";
    	#multithreaded opening up each month
	monthThr << Thread.new(base_url){ |url|
		eventThr = []
    		doc = Nokogiri::HTML(open(url))
		#seperating by the javascript
    		scripts = doc.css(".V9 script") 
		#puts scripts
		for x in scripts
			fParse(x.text)	
        	end
		scripts.css(".V10 script")
		for x in scripts
			fParse(x.text)	
        	end
  	
	}
end
monthThr.each{|t| t.join}

events.each do |event|
	bulk.find({id: event[:id]}).upsert.update({ "$set" => event})
end 
bulk.execute 
