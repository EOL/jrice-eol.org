require "rails_helper"

RSpec.describe "pages/show" do
  before do
    resource = instance_double("Resource", id: 64333,
      name: "Short Res Name")
    parent = instance_double("Node", ancestors: [],
      canonical_form: "Parent Taxon", page_id: 653421)
    node = instance_double("Node", ancestors: [parent])
    name = instance_double("Vernacular", string: "something common")
    lic1 = instance_double("License", name: "Image license name")
    lic2 = instance_double("License", name: "Article license name")
    image1 = instance_double("Medium", license: lic1, owner: "Owner 1",
      large_size_url: "some_url_580_360.jpg", name: "Image Name 1")
    image2 = instance_double("Medium", license: lic1, owner: "Owner 2",
      large_size_url: "another_url_580_360.jpg", name: "Image Name 2")
    article = instance_double("Article", name: "Article Name", license: lic2,
      body: "Article body", owner: "Article owner")
    traits = [
      { predicate: "http://predic.ate/one", measurement: "657",
        units: "http://un.its/one", resource_id: resource.id },
      { predicate: "http://predic.ate/one", term: "http://te.rm/one" },
      { predicate: "http://predic.ate/two", literal: "literal trait value" } ]
    glossary = {
      "http://predic.ate/one" => instance_double("Uri", name: "Predicate One"),
      "http://predic.ate/two" => instance_double("Uri", name: "Predicate Two"),
      "http://un.its/one" => instance_double("Uri", name: "Units URI"),
      "http://te.rm/one" => instance_double("Uri", name: "Term URI")
    }
    assign(:page, instance_double("Page", name: name, native_node: node,
      scientific_name: "<i>Nice scientific</i>", top_images: [image1, image2],
      top_articles: [article], traits: traits, glossary: glossary))
    assign(:resources, { resource.id => resource })
  end
  it "shows the title" do
    render
    expect(rendered).to match /Something Common/
    expect(rendered).to match /Nice scientific/
  end
  it "shows the top images' metadata" do
    render
    expect(rendered).to match /Image license name/
    expect(rendered).to match /Owner 1/
    expect(rendered).to match /Owner 2/
    expect(rendered).to match /Image Name 1/
    expect(rendered).to match /Image Name 2/
  end

  it "adds the default size to the image src" do
    render
    expect(rendered).to match /some_url_580_360.jpg/
    expect(rendered).to match /another_url_580_360.jpg/
  end

  it "shows the article" do
    render
    expect(rendered).to match /Article license name/
    expect(rendered).to match /Article Name/
    expect(rendered).to match /Article body/
    expect(rendered).to match /Article owner/
  end

  # TODO: I'm lazy; this requires another whole context...
  it "shows the article section name if article name is missing"

  it "shows the predicates" do
    render
    expect(rendered).to match /Predicate One/
    expect(rendered).to match /Predicate Two/
  end

  # TODO: I'm lazy. This requires Capybara or some clever RegEx.
  it "does not duplicate predicates"

  it "shows measurements and units" do
    render
    expect(rendered).to match /657\s+Units URI/
  end

  it "shows terms" do
    render
    expect(rendered).to match /Term URI/
  end

  it "shows literal trait values" do
    render
    expect(rendered).to match /literal trait value/
  end

  it "shows resource names when available" do
    render
    expect(rendered).to match /Short Res Name/
  end
end
