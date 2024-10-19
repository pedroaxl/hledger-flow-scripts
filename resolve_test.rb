require 'rspec/autorun'
require_relative './src/resolve.rb'
require 'rainbow'

describe Resolve do
    it "cleans up the description" do
        expect(Resolve.cleanup_description("Something/else")).to eq('Something\/else')
        expect(Resolve.cleanup_description("Something +1234")).to eq('Something \+1234')
        expect(Resolve.cleanup_description("Something *1234")).to eq('Something \*1234')
        expect(Resolve.cleanup_description("Something/else")).to eq('Something\/else')
    end
    it "cleans up installments in the description" do
        expect(Resolve.cleanup_description("Latam Site 2/4")).to eq("Latam Site")
    end 
    context "journals from multiple people" do
        before do 
            allow(Dir).to receive(:[]).with('./import/*').and_return(['/pedro','/livia'])
            allow(File).to receive(:directory?).with('/pedro').and_return(true)
            allow(File).to receive(:directory?).with('/livia').and_return(true)
        end
        it "journals from multiepl people should return false" do
            expect(Resolve.journals_from_multiple_people?).to be true
        end
        it "should convert account to rules file" do
            expect(Resolve.account_to_spec_rules_file("Liabilities:Lívia:Nubank:Cartão")).to eql("./import/livia/nubank/cartao/nubank-cartao-specific.rules")
            expect(Resolve.account_to_spec_rules_file("Assets:Lívia:Nubank:Conta")).to eql("./import/livia/nubank/conta/nubank-conta-specific.rules")
        end
        it "should convert expense account to rules file" do
            expect(Resolve.category_to_rules_file("Expenses:Lívia:Alimentação:Café")).to eql("./rules/expenses/alimentacao.psv")
            expect(Resolve.category_to_rules_file("Income:Lívia:Salário")).to eql("./rules/income.psv")

        end
    end
    context "journals from one person" do
        before do 
            allow(Dir).to receive(:[]).with('./import/*').and_return(['/pedro'])
            allow(File).to receive(:directory?).with('/pedro').and_return(true)
        end
        it "journals from multiepl people should return false" do
            expect(Resolve.journals_from_multiple_people?).to be false
        end
        it "should convert account to specific rules file" do
            expect(Resolve.account_to_spec_rules_file("Liabilities:Credit Cards:Nubank:Mastercard")).to eql("./import/pedro/nubank/creditcard/nubank-creditcard-specific.rules")
            expect(Resolve.account_to_spec_rules_file("Assets:Accounts:Nubank")).to eql("./import/pedro/nubank/account/nubank-account-specific.rules")
        end
        it "should convert expense account to rules file" do
            expect(Resolve.category_to_rules_file("Expenses:Home:Rent")).to eql("./rules/expenses/home.psv")
            expect(Resolve.category_to_rules_file("Income:Benefits")).to eql("./rules/income.psv")
        end
    end

    describe Resolve::Colorize do
      it "should colorize description blue and cyan" do
        expect(Resolve::Colorize.description("Something",0)).to eql(Rainbow("Something").bg(:blue))
        expect(Resolve::Colorize.description("Something",1)).to eql(Rainbow("Something").bg(:cyan))
      end
      it "should colorize amount" do
        expect(Resolve::Colorize.amount("R$100")).to eql(Rainbow("R$100").bg(:green))
        expect(Resolve::Colorize.amount("R$-100")).to eql(Rainbow("R$-100").bg(:red))

      end
      it "should generate colored category list" do
        category_list = ["A","B","C","D","E","F","G","H"]
        expected_colorized_categories = [Rainbow("A").bg(:red),Rainbow("B").bg(:green),Rainbow("C").bg(:yellow),Rainbow("D").bg(:blue),Rainbow("E").bg(:magenta),Rainbow("F").bg(:cyan),Rainbow("G").bg(:white),Rainbow("H").bg(:red)]
        expect(Resolve::Colorize.generate_category_list(category_list)).to eql(expected_colorized_categories)
      end
    end
end