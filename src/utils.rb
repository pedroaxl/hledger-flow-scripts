require 'digest'
require 'date'

class Utils

  # for preprocess

  def self.generate_transaction_id(bank_name, account_name, date, title, amount)
    combined_string = "#{bank_name}-#{account_name}-#{date}-#{title}-#{amount}"
    Digest::MD5.hexdigest(combined_string)
  end
  def self.convert_date_without_year(txn_date, bill_due_date)
    bill_date = Date.parse(bill_due_date)
    bill_year = bill_date.year
    txn_with_year = Date.parse("#{txn_date}/#{bill_year}")
    # If transaction date (with bill year) is before bill_due_date, use bill year
    # If transaction date (with bill year) is on or after bill_due_date, use previous year
    if txn_with_year < bill_date
      txn_with_year.to_s
    else # transaction date is on or after bill_due_date, so it was from previous year
      Date.parse("#{txn_date}/#{bill_year-1}").to_s
    end
  end
  def self.titleize(str)
    str.split(" ").map.with_index {|w,i| (w.capitalize if w.size > 1) or (w.downcase)}.join(" ")
  end
  def self.write_csv(csv, headers=nil)
    if headers
      headers.concat(csv.map {|l| l.join(",").strip}).join("\n")
    else
      csv.map {|l| l.join(",").strip}.join("\n")
    end
  end
  def self.empty_csv_with_header 
    [["date","code","title","amount"]]
  end
end