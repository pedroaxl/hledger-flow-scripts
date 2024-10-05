require 'csv'

class Wise
  class Account
    def self.read_csv(input_path)
      CSV.read(input_path)
    end
    def self.convert_date txn_date
      t = txn_date.split("-")
      "#{t[2]}-#{t[1]}-#{t[0]}"
    end
    def self.cleanup_desc desc
        desc.gsub("\"","").gsub(",",".")
    end
    def self.preprocess(csv)
      base_csv = csv.map{|l| [convert_date(l[1]),l[0], cleanup_desc(l[13] || l[4]), l[2], l[3]]}
      base_csv[0] = ["date","code","title","amount","currency"]
      base_csv
    end
  end
end