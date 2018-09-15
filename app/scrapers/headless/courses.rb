require 'watir'

def scrape_dep(browser)
	#browser.elements('class': 'toggle-sections-link-text').each do |elem|
	#	elem.parent.click()
	#end

	browser.elements('class': 'course').each do |elem|
		puts elem.text
	end
end

# Init headless browser
browser = Watir::Browser.new :chrome,  headless: true, url: "http://chromedriver:4444", :switches => ["disable-infobars", "no-sandbox"]
browser.goto 'https://app.testudo.umd.edu/soc/'
puts "asgfsaf"

# Iterate over all the department links
browser.elements(class: 'prefix-abbrev').each do |elem|
	puts elem.parent.text
	# Navigate to department
	elem.parent.click

	# Call scraper helper function
	scrape_dep(browser)

	# Return to SOC
	browser.back
end

# Clean up
browser.quit