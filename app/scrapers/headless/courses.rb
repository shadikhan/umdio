require 'watir'
require 'logger'

@logger = Logger.new(STDOUT)
@logger.level = Logger::WARN

def scrape_dep(browser)
	#browser.elements('class': 'toggle-sections-link-text').each do |elem|
	#	elem.parent.click()
	#end
	b = 0
	browser.elements('class': 'course').each do |elem|
		@logger.info(elem.text)
		b += 1
	end
end

# Init headless browser
browser = Watir::Browser.new :chrome,  headless: true, url: "http://chromedriver:4444", :switches => ["disable-infobars", "no-sandbox"]
browser.goto 'https://app.testudo.umd.edu/soc/'

@logger.info('test')

start = Time.now
# Iterate over all the department links
browser.elements(class: 'prefix-abbrev').each do |elem|
	@logger.info(elem.parent.text)
	# Navigate to department
	elem.parent.click
	
	# Call scraper helper function
	scrape_dep(browser)

	# Return to SOC
	browser.back
end
finish = Time.now

diff = (finish - start)

puts "Took #{diff} seconds"

# Clean up
browser.quit