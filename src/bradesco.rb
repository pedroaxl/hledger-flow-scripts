class Bradesco
  class Creditcard
    def self.read_csv input_path
      open(input_path, "r:ISO-8859-1:UTF-8") { |io| io.read.split("\r") }
    end

    def self.filter_txn_lines csv
      header_lines = csv.collect.with_index{|r,i| i+2 if r.include?"PEDRO K AXELRUD"}.compact
      line_breaks = csv.collect.with_index{|r,i| i-1 if r.empty?}.compact
      txn_blocks_ranges = header_lines.map do |header_line|
        [header_line, line_breaks.select{|l| l > header_line}.first]
      end
      txn_blocks_ranges.map {|tr| csv[tr[0]..tr[1]]}.flatten
    end

    def self.convert_date txn_date, bill_due_date
      Utils.convert_date_without_year(txn_date, bill_due_date)
    end

    def self.convert_amount amt
      amt.gsub(".","").gsub(",",".")
    end

    def self.is_installment? title
      /(\d{1,2})\/\d{1,2}$/.match? title
    end

    def self.adjusted_installment_date txn
      installment_number = /(\d{1,2})\/\d{1,2}$/.match(txn[2])[1].to_i
      raise "Couldn't parse installment number for transaction" + txn.inspect if installment_number == 0
      (Date.parse(txn[0]) >>(installment_number - 1)).to_s
    end

    def self.cleanup_installment_title(title)
      match = /^(PARC=\d{3}|Parc=\d{3})(.*)/.match(title)
      (Utils.titleize(match[2]) if match) || title
    end

    def self.generate_transaction_id(date, title, amount)
      Utils.generate_transaction_id("bradesco", "creditcard", date, title, amount)
    end

    def self.preprocess csv, bill_due_date
      csv = filter_txn_lines(csv).map{|l| l.split(";")}
      base_csv = csv.map {|l| [convert_date(l[0], bill_due_date), nil, Utils.titleize(l[1]), convert_amount(l[3])]}
      base_csv.delete_if {|l| l[2] == "Saldo Anterior"}
      base_csv.delete_if {|l| l[2] == "Pag Boleto Bancario"}
      base_csv.each do |l|
        if is_installment?(l[2])
          l[0] = adjusted_installment_date(l) 
          l[2] = cleanup_installment_title(l[2])
        end
        l[1] = generate_transaction_id(l[0],l[2],l[3])
      end
      Utils.empty_csv_with_header + base_csv
    end

  end
end