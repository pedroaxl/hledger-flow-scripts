#!/usr/bin/env ruby
require 'csv'
require 'yaml'

CONFIG = YAML.load_file('config.yml')

def cleanup_description(desc)
    if /(\d{1,2})\/\d{1,2}$/.match? desc
        match = /(.*)(\d{1,2}\/\d{1,2})$/.match(desc)
        desc = match[1].strip
    end
    desc.gsub("*",'\*')
end

def account_txn_match(txn)
    if txn[:code]
        txn[:code]
    end
end

def account_to_spec_rules_file account
    account_parsed = account.split(':')
    case account_parsed[1]
    when "Accounts"
        "./import/#{CONFIG["person_name"]}/#{account_parsed[2].downcase}/account/#{account_parsed[2].downcase}-account-specific.rules"
    when "Credit Cards"
        "./import/#{CONFIG["person_name"]}/#{account_parsed[2].downcase}/creditcard/#{account_parsed[2].downcase}-creditcard-specific.rules"
    else
        raise "Couldn't parse account specific rules path"
    end
end

def category_to_rules_file category
    c = category.split(":")
    "./rules/#{c[0].downcase}/#{c[1].downcase}.psv"
end

def match_to_if_block(match_str, account)
    "#{match_str}|#{account}"
end

def match_to_specific_if_block(match_str, account, comment)
    "#{match_str}|#{account}|#{comment}"
end

def parse_csv_line(l)
    {"index": l[0], "date": l[1], "code":l[2], "description":l[3], "account": l[4], "amount":l[5] }
end


csv = CSV.new(`hledger --file import/#{CONFIG["person_name"]}/all-years.journal --period 2024 print unknown | hledger -f - register -I -O csv`).read

transactions = []
csv.each do |l|
    line = parse_csv_line(l)
    next if line[:index] == "txnidx"
    transactions.push(line) unless line[:account].include?("unknown")
end


category_rules = Dir["./rules/*.psv","./rules/expenses/*.psv"].map {|path| File.read(path).split("\n") }.flatten.delete_if {|t| t == "if|account2"}
other_accounts = File.read("./rules/other_accounts.txt").split("\n")
category_list = category_rules.map{|c| c.split("|")[1]}.concat(other_accounts).uniq!.sort

loop do
    txns_list = transactions.map do |t| 
        [t[:date],t[:description],t[:account],t[:amount]].join("|") + "\n"
    end

    break if transactions.empty?
    txn_raw = `echo '#{txns_list.join}' | sk --ansi --header="Choose transaction" -d '|' --tac --case=ignore`
    break if txn_raw.empty?
    txn = txn_raw.split("|")
    txn_full = transactions.select{|t| t[:date] == txn[0] and t[:description] == txn[1]}.first

    category = `echo '#{category_list.join("\n")}' | sk --ansi --header="Choose category"  --tac --case=ignore`.strip.split("\n")[0]
    break if category.nil?

    # IS THIS TXN SPECIFIC ? [Y]/N
    specific_txn = `echo 'YES\nNO' | sk --header="Is this category for a specific transaction?" --ansi --print-cmd -i`.strip 
    break if specific_txn.empty?

    if specific_txn == "YES"
        comment = `echo '#{txn_raw}#{category}' | sk --header="Enter comment (prepend : to inhibit selection)" --ansi --print-cmd -i` 
        comment = comment.split("\n")[0]
        comment = nil if (comment == ":" or comment.empty?)
        rule = match_to_specific_if_block(account_txn_match(txn_full),category, comment)
        rules_file_path = account_to_spec_rules_file(txn_full[:account])
        transactions.delete_if{|t| t[:code] == txn_full[:code]}
    else
        rule = match_to_if_block(cleanup_description(txn_full[:description]),category)
        rules_file_path = category_to_rules_file(category)
        transactions.delete_if{|t| t[:description] == txn_full[:description]}
    end
    File.open(rules_file_path, "a+") {|f| f.write("\n"+rule)}
end


