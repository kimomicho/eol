require File.dirname(__FILE__) + '/../spec_helper'

describe 'Account user profile page (HTML)' do

  before(:all) do
    load_foundation_cache
    Capybara.reset_sessions!
    @credentials = 'This has a <a href="linky">link</a> <b>this is bold<br />as is this</b> and <script type="text/javascript">alert("hi");</script>'
    @user        = build_curator(HierarchyEntry.gen, :credentials => @credentials)
    visit("/account/show/#{@user.id}") # cache the response the taxon page gives before changes
    @body = body
  end

  it 'should allow links in credentials' do
    @body.should have_tag('a[href="linky"]')
  end
  
  it 'should NOT allow javascript in credentials' do
    @body.should_not have_tag('script', :text => 'alert("hi");')
  end

  it 'should have a working BR tag in credentials' do
    @body.should have_tag('div#credentials') do
      with_tag('br')
    end
  end

end
