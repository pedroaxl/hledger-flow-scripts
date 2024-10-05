require 'csv'

class Nubank
  class Account
    def self.read_csv(input_path)
      CSV.read(input_path)
    end
    def self.description_cleanup(description)
      description.gsub!(",","")
      f = description.split(" - ")
      case description
      when /(Transfer\ência)/
        "Transferência #{f[1]}"
      when /(Pagamento de boleto efetuado)/
        "Boleto #{f[1]}"
      else
        description
      end
    end
    def self.preprocess(csv)
      csv[0] = ["date","code","title","amount"]
      csv.each {|l| l[3] = description_cleanup(l[3])}
    end
  end


  class Creditcard
    def self.read_csv(input_path)
      File.read(input_path).gsub("\"","").split("\n").map{|l| l.split(",")}
    end
    def self.generate_transaction_id(date, title, amount)
      Utils.generate_transaction_id("nubank", "creditcard", date, title, amount)
    end
    def self.new_format?(csv_header)
      csv_header == ["date", "title", "amount"]
    end
    def self.preprocess(csv)
      csv.map!{|l| [l[0],nil,l[1],l[2]]} if new_format?(csv[0])
      csv[0] = ["date","code","title","amount"]
      csv.each do |l|
        next if l[0] == "date" 
        l[1] = generate_transaction_id(l[0],l[2],l[3])
      end
    end
  end

end
