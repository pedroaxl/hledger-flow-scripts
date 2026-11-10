class Bradesco
  class Creditcard
    def self.read_csv input_path
      open(input_path, "r:ISO-8859-1:UTF-8") { |io| io.read.split("\r") }
    end

    def self.filter_txn_lines csv
      header_lines = csv.collect.with_index{|r,i| i+2 if r.include?"PEDRO K AXELRUD"}.compact
      # Find line breaks (empty lines or lines starting with "Total da fatura")
      line_breaks = csv.collect.with_index do |r, i|
        stripped = r.strip
        i if stripped.empty? || stripped.start_with?("Total da fatura")
      end.compact
      
      # Find the last valid transaction line (before "Total da fatura" or end of file)
      last_txn_line = csv.length - 1
      csv.each_with_index do |r, i|
        if r.strip.start_with?("Total da fatura")
          last_txn_line = i - 1
          break
        end
      end
      
      txn_blocks_ranges = header_lines.map do |header_line|
        # Find the next line break after this header, or the next header, whichever comes first
        next_break = line_breaks.select{|l| l > header_line}.first
        next_header = header_lines.select{|h| h > header_line}.first
        end_line = [next_break, next_header].compact.min
        # If no end_line found, use last_txn_line
        end_line ||= last_txn_line + 1
        # Don't go beyond last_txn_line
        end_line = [end_line, last_txn_line + 1].min
        [header_line, end_line - 1]
      end
      
      # Extract lines from each block, avoiding duplicates
      result = []
      txn_blocks_ranges.each do |tr|
        result.concat(csv[tr[0]..tr[1]])
      end
      result
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

    # Em compras parceladas o Bradesco repete a data da compra em todas as faturas,
    # então a parcela N é deslocada N-1 meses. Algumas cobranças (ex.: anuidade) já
    # vêm com a data do mês; deslocá-las passaria do vencimento da própria fatura,
    # o que é impossível, e nesse caso a data da fatura é mantida.
    def self.adjusted_installment_date txn, bill_due_date = nil
      installment_number = /(\d{1,2})\/\d{1,2}$/.match(txn[2])[1].to_i
      raise "Couldn't parse installment number for transaction" + txn.inspect if installment_number == 0
      shifted = Date.parse(txn[0]) >> (installment_number - 1)
      return txn[0] if bill_due_date && shifted >= Date.parse(bill_due_date)
      shifted.to_s
    end

    def self.cleanup_installment_title(title)
      match = /^(PARC=\d{3}|Parc=\d{3})(.*)/.match(title)
      (Utils.titleize(match[2]) if match) || title
    end

    def self.generate_transaction_id(date, title, amount)
      Utils.generate_transaction_id("bradesco", "creditcard", date, title, amount)
    end

    def self.preprocess csv, bill_due_date
      csv = filter_txn_lines(csv).map{|l| l.split(";")}.reject{|l| l.empty? || l.all?(&:empty?) || !l[0] || !/^\d{2}\/\d{2}$/.match?(l[0].strip)}
      base_csv = csv.map {|l| [convert_date(l[0], bill_due_date), nil, Utils.titleize(l[1]), convert_amount(l[3])]}
      base_csv.delete_if {|l| l[2] == "Saldo Anterior"}
      base_csv.delete_if {|l| l[2] == "Pag Boleto Bancario"}
      base_csv.each do |l|
        if is_installment?(l[2])
          l[0] = adjusted_installment_date(l, bill_due_date)
          l[2] = cleanup_installment_title(l[2])
        end
        l[1] = generate_transaction_id(l[0],l[2],l[3])
      end
      Utils.empty_csv_with_header + base_csv
    end

  end
end