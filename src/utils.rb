require 'digest'
require 'date'

class Utils

  # for preprocess

  def self.generate_transaction_id(bank_name, account_name, date, title, amount)
    combined_string = "#{bank_name}-#{account_name}-#{date}-#{title}-#{amount}"
    Digest::MD5.hexdigest(combined_string)
  end
  def self.convert_date_without_year(txn_date, bill_due_date)
    if Date.parse("#{txn_date}/#{Date.today.year}") < Date.parse(bill_due_date)
      Date.parse("#{txn_date}/#{Date.today.year}").to_s
    else # if in the future means it was past year
      Date.parse("#{txn_date}/#{Date.today.year-1}").to_s
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