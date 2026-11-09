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
    # Newer Nubank creditcard exports quote the amount and use the Brazilian
    # number format (comma as decimal separator, dot as thousands separator),
    # e.g. `"24,76"`, `"1.333,07"` or `"- 12.522,57"`. Older exports use an
    # unquoted dot-decimal amount (`52.00`). This regex detects the newer
    # dialect by looking for a quoted comma-decimal amount at end of a line.
    NEW_VALUE_FORMAT_AMOUNT = /,"-?\s*[\d.]+,\d{2}"\s*$/

    def self.read_csv(input_path)
      raw = File.read(input_path)
      if new_value_format?(raw)
        # Proper RFC-4180 CSV: parse respecting quotes, then drop any inner
        # literal quotes from fields (matching the legacy quote-stripping).
        CSV.parse(raw).map { |row| row.map { |f| f&.gsub("\"", "") } }
      else
        # Legacy files contain bare/improper quotes inside titles that a strict
        # CSV parser would reject; keep the original naive parsing for them.
        raw.gsub("\"","").split("\n").map{|l| l.split(",")}
      end
    end
    def self.new_value_format?(raw)
      raw.each_line.drop(1).any? { |l| l =~ NEW_VALUE_FORMAT_AMOUNT }
    end
    # Convert a Brazilian-formatted amount ("- 12.522,57") to a plain
    # dot-decimal value ("-12522.57"). Amounts without a comma (the legacy
    # dot-decimal format) are returned unchanged, keeping old files identical.
    def self.normalize_amount(amount)
      a = amount.to_s.strip
      return a unless a.include?(",")
      sign = a.start_with?("-") ? "-" : ""
      int, frac = a.gsub(/[^\d,]/, "").split(",")
      "#{sign}#{int}.#{frac}"
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
        l[3] = normalize_amount(l[3])
        l[1] = generate_transaction_id(l[0],l[2],l[3])
      end
    end
  end

end
