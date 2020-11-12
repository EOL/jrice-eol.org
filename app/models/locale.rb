# Represents an I18n 'locale', which is really a language code

require 'csv'

class Locale < ApplicationRecord
  has_many :languages
  has_many :ordered_fallback_locales
  validates :code, presence: true, uniqueness: true

  before_validation { code.downcase! }

  default_scope { includes(:languages) }

  CSV_PATH = Rails.application.root.join('db', 'seed_data', 'language_groups_locales.csv')

  def fallbacks
    self.ordered_fallback_locales.includes(:fallback_locale).order(position: 'asc').map { |r| r.fallback_locale }
  end

  class << self
    def current
      Locale.find_by_code(I18n.locale.downcase) || Locale.find_by_code(I18n.default_locale.downcase)
    end

    def english
      Locale.find_by_code("en")
    end

    # INTENDED FOR OFFLINE USE ONLY
    def rebuild_language_mappings
      rows = CSV.read(CSV_PATH, headers: true, skip_blanks: true)
      puts 'updating language -> locale mappings'
      update_language_locales(rows)
      puts 'done'
    end

    def all_by_code
      @all_by_code ||= Locale.all.map { |l| [l.code, l] }.to_h
    end


    def get_or_create!(code)
      code = code.downcase

      if all_by_code.include?(code)
        all_by_code[code]
      else
        puts "Locale #{code} not found in db, creating..."
        new_locale = Locale.create!(code: code)
        all_by_code[code] = new_locale
        new_locale
      end
    end
    # END

    private

    def update_language_locales(rows)
      self.transaction do
        rows.each do |row|
          puts "handling row #{row}"

          languages = Language.where(group: row['language_group'])
          locale = get_or_create!(row['locale'])

          languages.each do |language|
            language.locale = locale
            language.save! 
          end
        end
      end
    end
  end
end
