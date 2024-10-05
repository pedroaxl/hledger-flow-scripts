require 'csv'

class Itau
  class Account
    def self.read_csv input_path
      CSV.read(input_path, col_sep: ";", headers: false)
    end

    def self.convert_date txn_date
      t = txn_date.split("/")
      "#{t[2]}-#{t[1]}-#{t[0]}"
    end

    def self.convert_amount amt
      amt.gsub(".","").gsub(",",".")
    end

    def self.generate_transaction_id(date, title, amount)
      Utils.generate_transaction_id("itau", "account", date, title, amount)
    end

    def self.preprocess csv
      base_csv = csv.map {|l| [l[0], nil, l[1], l[2]]}
      base_csv.each do |line|
        line[0] = convert_date line[0]
        line[2] = Utils.titleize(line[2])
        line[3] = convert_amount line[3]
        line[1] = generate_transaction_id(line[0], line[2], line[3])
      end
      Utils.empty_csv_with_header + base_csv
    end

  end
end