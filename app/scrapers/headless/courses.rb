require 'watir'
require 'nokogiri'
require 'logger'
require 'pg'

@logger = Logger.new(STDOUT)
@logger.level = Logger::INFO

@db = PG.connect( host: 'postgres', user: 'postgres', dbname: 'umdio' )

# safely formats to UTF-8
def utf_safe text
	if !text.valid_encoding?
	  text = text.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
	end
	text
end

def parse_course(div)
	# Import div into nokogiri to parse
	course = Nokogiri::HTML.parse div.outer_html()
	
	course_id = course.search('div.course-id').text
    course_title = course.search('span.course-title').text
    credits = course.search('span.course-min-credits').text

    # courses have 2 'course texts': approved-course-texts and course-texts
    # approved-course-texts has 2 child divs: relationships and description (if there are any relationships)
    # other course-texts will have relationships mixed in with description
    # 
    # if course has both approved-course-text and course-texts, only first set of 
    #     relationships will be parsed. anything in course-texts will be placed in "additional info"
    #
    # algorithm finds relationships and, if they exist, removes them from the description
    # searches both approved-course-texts > div:first-child and course-texts > div for relationships
    # leftover text will either be description (if approved-course-texts is empty) or additional info

    approved = course.search('div.approved-course-texts-container')
    other = course.search('div.course-texts-container')

    # get all relationship text
    if approved.css('> div').length > 1 
      text = approved.css('> div:first-child').text.strip + other.css('> div').text.strip
    else 
      text = other.css('> div').text.strip
    end

    text = utf_safe text

    # match all relationships, remove them from the description

    match = /Prerequisite: ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    prereq = match ? match[1] : nil


    match = /Corequisite: ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    coreq = match ? match[1] : nil

    match = /(?:Restricted to)|(?:Restriction:) ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    restrictions = match ? match[1] : nil

    match = /Credit (?:(?:only )|(?:will be ))?granted for(?: one of the following)?:? ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    credit_granted_for = match ? match[1] : nil

    match = /Also offered as:? ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    also_offered_as = match ? match[1] : nil


    match = /Formerly:? ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    formerly = match ? match[1] : nil

    match = /Additional information: ([^.]+\.)/.match(text)
    text = match ? text.gsub(match[0], '') : text
    additional_info = match ? match[1] : nil

    # if approved-course-texts held relationships, use 2nd child as description and leftover text as "additional info"
    if approved.css('> div').length > 0 

      description = (utf_safe approved.css('> div:last-child').text).strip.gsub(/\t|(\r\n)/, '')
      additional_info = additional_info ? additional_info += ' '+text : text
      additional_info = additional_info && additional_info.strip.empty? ? nil : additional_info.strip

    elsif other.css('> div').length > 0 
      description = text.strip.empty? ? nil : text.strip
    end

    relationships = {
      prereqs: prereq,
      coreqs: coreq,
      restrictions: restrictions,
      credit_granted_for: credit_granted_for,
      also_offered_as: also_offered_as,
      formerly: formerly,
      additional_info: additional_info 
    }

    return {
      course_id: course_id,
      name: course_title,
      credits: course.css('span.course-min-credits').first.content,
      grading_method: course.at_css('span.grading-method abbr') ? course.at_css('span.grading-method abbr').attr('title').split(', ') : [],
      core: utf_safe(course.css('div.core-codes-group').text).gsub(/\s/, '').delete('CORE:').split(','),
      gen_ed: utf_safe(course.css('div.gen-ed-codes-group').text).gsub(/\s/, '').delete('General Education:').split(','),
      description: description,
      relationships: relationships
    }
end

def parse_sections(div, dept)
	sections = Nokogiri::HTML.parse(div.outer_html)

	sections.search('div.section').each do |section|
		# Professors
		instructors = section.search('span.section-instructors').text.gsub(/\t|\r\n/,'').encode('UTF-8', :invalid => :replace).split(',').map(&:strip)

		# add course and department to professor object for each instructor
		instructors.each do |x|
		if x != 'Instructor: TBA'
			professor_name = x.squeeze()
			profs[professor_name] ||= {:courses => [], :depts => []}
			profs[professor_name][:courses] |= [course_id]
			profs[professor_name][:depts] |= [dept]
		end
		end
	end
	

	meetings = []
	section.search('div.class-days-container div.row').each do |meeting|
	  start_time = meeting.search('span.class-start-time').text
	  end_time = meeting.search('span.class-end-time').text

	  meetings << {
		:days => meeting.search('span.section-days').text,
		:start_time => start_time,
		:end_time => end_time,
		:start_seconds => time_to_int(start_time),
		:end_seconds => time_to_int(end_time),
		:building => meeting.search('span.building-code').text,
		:room => meeting.search('span.class-room').text,
		:classtype => meeting.search('span.class-type').text || "Lecture"
	  }
	end
	number = section.search('span.section-id').text.gsub(/\s/, '')
	section_array << {
	  :section_id => "#{course_id}-#{number}",
	  :course => course_id,
	  :number => number,
	  :instructors => section.search('span.section-instructors').text.gsub(/\t|\r\n/,'').encode('UTF-8', :invalid => :replace).split(',').map(&:strip),
	  :seats  => section.search('span.total-seats-count').text,
	  :semester => semester,
	  :meetings => meetings
	}
	e
end

# TODO: get dept name and id here
def scrape_department(browser)
	# Get dept name and code
	dept_id = browser.span('class': 'course-prefix-abbr').text()
	dept_name = browser.span('class': 'course-prefix-name').text()

	browser.elements('class': 'toggle-sections-link-text').each do |elem|
		browser.execute_script('arguments[0].scrollIntoView();', elem)
		elem.click()
	end

	courses = []
	browser.elements('class': 'course').each do |elem|
		courses << parse_course(elem)
	end

	sections = []
	browser.elements('class': 'sections-container').each do |elem|
		sections += parse_sections(elem)
	end
end

def scrape_semester(semester)	
	# Create tables
	sql = File.open('courses.sql', 'rb') { |file| file.read }
	begin
		@db.exec(sql)
		@db.exec("ALTER TABLE courses RENAME TO courses#{semester}")
		@db.exec("ALTER TABLE sections RENAME TO sections#{semester}")
	rescue PG::Error
		@logger.warn "Tables already exist for semester #{semester}"
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

scrape_semester('201808')