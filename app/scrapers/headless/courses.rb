require 'watir'
require 'logger'
require 'pg'

@logger = Logger.new(STDOUT)
@logger.level = Logger::WARN

def scrape_department(browser)
	browser.elements('class': 'toggle-sections-link-text').each do |elem|
		browser.execute_script('arguments[0].scrollIntoView();', elem)
		elem.click()
	end

	browser.elements('class': 'course').each do |elem|
		@logger.info(elem.text)
	end
end

def scrape_semester(semester)
	# Create tables
	sql = File.open('../../courses.sql', 'rb') { |file| file.read }
	with_db do |db|
	begin
		db.exec(sql)
	rescue PG::Error
		#####
	end

	# Init headless browser
	browser = Watir::Browser.new :chrome,  headless: true, url: "http://chromedriver:4444", :switches => ["disable-infobars", "no-sandbox"]
	browser.goto 'https://app.testudo.umd.edu/soc/'

	start = Time.now

	# Iterate over all the department links
	browser.elements(class: 'prefix-abbrev').each do |elem|
		@logger.info(elem.parent.text)
		# Navigate to department
		elem.parent.click

		# Call scraper helper function
		scrape_department(browser)

		# Return to SOC
		browser.back
	end

	finish = Time.now
	diff = (finish - start)
	puts "Took #{diff} seconds"

	# Clean up
	browser.quit
end