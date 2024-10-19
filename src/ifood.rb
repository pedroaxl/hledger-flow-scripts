require 'csv'

class Ifood
    class Account
        def self.read_csv(input_path)
          File.read(input_path).gsub("\"","").split("\n").map{|l| l.split(",")}
        end
        def self.generate_transaction_id(date, title, amount)
          Utils.generate_transaction_id("ifood", "account", date, title, amount)
        end
        def self.preprocess(csv)
          csv.map do |l|
            if l[0] == "date"
                ["date","code","title","amount"] 
            else
                [l[0], generate_transaction_id(l[0],l[1],l[2]), l[1],l[2]]
            end
          end
        end
      end
end