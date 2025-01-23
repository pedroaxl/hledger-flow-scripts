require 'i18n'
require 'rainbow'
require 'csv'
require 'json'


I18n.available_locales = [:en]
COLORS = [:red, :green, :yellow, :blue, :magenta, :cyan, :white] # removed :black


class Resolve

  def self.cleanup_description(desc)
    if /(\d{1,2})\/\d{1,2}$/.match? desc
        match = /(.*)(\d{1,2}\/\d{1,2})$/.match(desc)
        desc = match[1].strip
    end
    desc.gsub("*",'\*').gsub("\+", '\\\+').gsub(/\//,'\/')
  end

  def self.journals_from_multiple_people?  
    Dir["./import/*"].map{|p| File.directory?(p)}.count(true) > 1
  end

  def self.account_to_spec_rules_file account
    account_parsed = account.split(':')
    bank_name = I18n.transliterate(account_parsed[2]).downcase
    if Resolve.journals_from_multiple_people? 
        person_name = I18n.transliterate(account_parsed[1]).downcase
        account_name = I18n.transliterate(account_parsed[3].gsub(" ","")).downcase
    else
        person_name = I18n.transliterate(Dir["./import/*"].filter{|p| File.directory?(p)}.first.split("/").last)
        account_name = I18n.transliterate(account_parsed[1].gsub(" ","")).downcase
        account_name.chop! if account_name[-1] == "s" # remove plural
    end
    "./import/#{person_name}/#{bank_name}/#{account_name}/#{bank_name}-#{account_name}-specific.rules"

  end

  def self.category_to_rules_file category
    c = category.split(":")
    if Resolve.journals_from_multiple_people?
      "./rules/#{I18n.transliterate(c[1]).downcase}/#{c[0].downcase}.psv"
    else
      if c.size == 2
        "./rules/#{c[0].downcase}.psv"
      else
        "./rules/#{c[0].downcase}/#{I18n.transliterate(c[1]).downcase}.psv"
      end
    end
  end

  class Colorize
    def self.description(description, i)
      Rainbow(description).bg(i % 2 == 0 ? :blue : :cyan)
    end

    def self.account(account,high_level_category_colors,category_key_range)
      Rainbow(account).bg(high_level_category_colors[account.split(":")[category_key_range].join(":")])
    end

    def self.amount amount
      Rainbow(amount).bg(amount.match(/([\d|\.|\-]+)/)[0].to_i > 0 ? :green : :red)
    end

    def self.generate_category_list category_list
      category_key_range = Resolve.journals_from_multiple_people? ? 0..2 : 0..1
      high_level_list = category_list.map{|c| c.split(":")[category_key_range].join(":")}.uniq
      high_level_category_colors = {}
      high_level_list.each_with_index {|c,i| high_level_category_colors[c] = COLORS[(i % COLORS.size)]}
      category_list.map {|c| account(c,high_level_category_colors, category_key_range)}
    end

  end

  class Hledger
    def self.get_unknown_transactions starting_year=nil
      period_arg = starting_year ? ("--period '" + starting_year + "'") : ""
      CSV.new(`hledger --file import/all-years.journal #{period_arg} print unknown | hledger -f - register -I -O csv`).read
    end

    def self.generate_category_list rules_directories, accounts_list_file_path
      category_rules = Dir.glob(rules_directories).map {|path| File.read(path).split("\n") }.flatten.delete_if {|t| t == "if|account2"}
      other_accounts = File.read(accounts_list_file_path).split("\n") rescue []
      category_list = category_rules.map{|c| c.split("|")[1]}.concat(other_accounts).uniq!.sort rescue other_accounts
    end
  end

  def self.generate_transactions_list_for_loop transactions
    transactions.map.with_index do |t,i|
      [t[:date],Colorize.description(t[:description],i),t[:account],Colorize.amount(t[:amount])].join("|") + "\n"
    end
  end

  def self.parse_csv_line(l)
    {"index": l[0], "date": l[1], "code":l[2], "description":l[3], "account": l[4], "amount":l[5], "type": (l[5].gsub("R$","").to_f > 0 ? :credit : :debit) }
  end

  def self.generate_transactions_from_csv csv
    transactions = []
    csv.each do |l|
      line = parse_csv_line(l)
      next if line[:index] == "txnidx"
      transactions.push(line) unless line[:account].include?("unknown")
    end
    transactions
  end

  def self.match_to_specific_if_block(txn, account, comment)
    "#{txn[:code]}|#{account}|#{comment}"
  end

  def self.match_to_if_block(match_str, account)
    "#{match_str}|#{account}"
  end

  # batch processing methods

  class Batch
    def self.group_transactions_by_date transactions
      txns_grouped = transactions.group_by {|t| [t[:date], t[:account], t[:type]]}
      txns_grouped.map do |date_account_type, txns|
        {"date":date_account_type[0], "account": date_account_type[1], "type": date_account_type[2], "count": txns.count, "amount": txns.sum{|t| t[:amount].gsub("R$","").to_f}}
      end
    end

    def self.generate_grouped_transactions_list_for_loop transactions
      transactions.filter{|t| t[:count] > 5}.map do |t|
        [t[:date],t[:account],t[:type], "count: "+ t[:count].to_s, "amount: " + t[:amount].to_s].join("|") + "\n"
      end
    end

    def self.filter_transactions_from_date_type transactions, query_string
      q = query_string.split("|")
      transactions.filter{|t| t[:date] == q[0] and t[:account] == q[1] and t[:type] == q[2].to_sym}
    end

    def self.summary_message query_string, category
      q = query_string.split("|")
      [ "\nAre you sure?\n\n",
      "######## SUMMARY #########\n",
      "Date: #{q[0]}\n",
      "Account: #{q[1]}\n",
      "Type: #{q[2]}\n",
      (q[3].capitalize + "\n"),
      q[4].capitalize.strip + "\n",
      "Category: #{category.strip}\n"
    ].reverse
    end
  end

end