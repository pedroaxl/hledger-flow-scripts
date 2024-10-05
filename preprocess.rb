#!/usr/bin/env ruby
require_relative './src/utils.rb'
require_relative './src/bradesco.rb'
require_relative './src/nubank.rb'
require_relative './src/itau.rb'
require_relative './src/wise.rb'


#### Main
# Expect 4 args: input_statement_path, output_statement_path, bank_name, account_name, owner
case ARGV.size
when 5
  input_path, output_path, bank_name, account_name, _owner = ARGV
else
  raise "Expect 4 args: input_statement_path, output_statement_path, bank_name, account_name, owner \n Received #{ARGV.inspect}"
end

csv_headers = ["date,code,title,amount"]

case bank_name
when 'nubank'
  case account_name
  when 'account'
    csv = Nubank::Account.read_csv(input_path)
    output = Utils.write_csv(Nubank::Account.preprocess(csv))
  when 'creditcard'
    csv = Nubank::Creditcard.read_csv(input_path)
    output = Utils.write_csv(Nubank::Creditcard.preprocess(csv))
  end
when 'bradesco'
  csv = Bradesco::Creditcard.read_csv(input_path)
  bill_due_date = "#{input_path.split("/").last.split(".").first}-01"
  output = Utils.write_csv(Bradesco::Creditcard.preprocess(csv, bill_due_date))
when 'itau'
  csv = Itau::Account.read_csv(input_path)
  output = Utils.write_csv(Itau::Account.preprocess(csv))
when 'wise'
  csv = Wise::Account.read_csv(input_path)
  output = Utils.write_csv(Wise::Account.preprocess(csv))
else
  raise "Don't know how to process this #{bank_name} #{bank_account}"
end

File.open(output_path,"w") {|f| f.write(output)}