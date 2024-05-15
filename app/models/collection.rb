class Collection < ApplicationRecord
  # searchkick

  before_destroy :remove_owners

  has_many :collection_associations, -> { order(position: :asc) }, inverse_of: :collection, dependent: :destroy
  has_many :collections, through: :collection_associations, source: :associated
  has_many :collected_pages, -> { order("position asc") }, inverse_of: :collection, dependent: :destroy
  has_many :pages, -> { order("collected_pages.created_at desc") }, through: :collected_pages

  has_and_belongs_to_many :users

  accepts_nested_attributes_for :collection_associations, allow_destroy: true
  accepts_nested_attributes_for :collected_pages, allow_destroy: true

  validates :name, presence: true

  enum collection_type: [ :normal, :gallery ]
  enum default_sort: [ :position, :sci_name, :sci_name_rev, :sort_field, :sort_field_rev, :hierarchy ]

  def empty?
    collected_pages.empty? && collection_associations.empty?
  end

  private

  def remove_owners
    users = []
    save
  end
end
