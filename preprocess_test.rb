require 'rspec/autorun'
require_relative './src/utils.rb'
require_relative './src/bradesco.rb'
require_relative './src/nubank.rb'
require_relative './src/itau.rb'
require_relative './src/wise.rb'


require 'digest'


describe Utils do
    it "generates transaction id" do
        test_txn = "a-b-c-d-e"
        expect(Utils.generate_transaction_id("a","b","c","d","e")).to eq Digest::MD5.hexdigest(test_txn)
    end
    
    it "converts dates from this year" do
        expect(Utils.convert_date_without_year("05/08","2024-09-01")).to eq("2024-08-05")
    end

    it "converts dates from next year" do
        expect(Utils.convert_date_without_year("05/08","2024-07-01")).to eq("2023-08-05")
    end

    it "titleize different types of titles" do
        expect(Utils.titleize("PAG*Ricardo ")).to eq("Pag*ricardo")
        expect(Utils.titleize("PG *BRAVO CONCEPT 1/5")).to eq("Pg *bravo Concept 1/5")
        expect(Utils.titleize("PARC=102SOLEM ODONTOLOG 1/2")).to eq("Parc=102solem Odontolog 1/2")
        expect(Utils.titleize("CARACOL BAR E RESTAURANT ")).to eq("Caracol Bar e Restaurant")
        expect(Utils.titleize("LOJA MO.D ")).to eq("Loja Mo.d")
    end
end

describe Bradesco::Creditcard do
    it "should filter transaction lines" do
        csv = ["Something","PEDRO K AXELRUD ;;; 9846","Data;Hist�rico;Valor(US$);Valor(R$);","22/11;PAYPAL *HTCLICK 8/12;0,00;815,00","30/11;AGENCIA DE VIAGENS 8/10;0,00;3844,93",""]
        expect(Bradesco::Creditcard.filter_txn_lines(csv)).to eq(["22/11;PAYPAL *HTCLICK 8/12;0,00;815,00", "30/11;AGENCIA DE VIAGENS 8/10;0,00;3844,93"])
    end
    it "should filter transaction lines with multiple cards" do
        csv = ["Something","PEDRO K AXELRUD ;;; 9846","Data;Hist�rico;Valor(US$);Valor(R$);","22/11;PAYPAL *HTCLICK 8/12;0,00;815,00","30/11;AGENCIA DE VIAGENS 8/10;0,00;3844,93","","PEDRO K AXELRUD ;;; 1770","Data;Hist�rico;Valor(US$);Valor(R$);","20/08;ANUIDADE DIFERENCIADA 1/12;0,00;154,00","09/08;CUSTO TRANS. EXTERIOR-IOF ;0,00;30,48"]
        expect(Bradesco::Creditcard.filter_txn_lines(csv)).to eq(["22/11;PAYPAL *HTCLICK 8/12;0,00;815,00", "30/11;AGENCIA DE VIAGENS 8/10;0,00;3844,93","20/08;ANUIDADE DIFERENCIADA 1/12;0,00;154,00","09/08;CUSTO TRANS. EXTERIOR-IOF ;0,00;30,48"])
    end
    it "should convert transaction date" do
        expect(Bradesco::Creditcard.convert_date("05/08","2023-08-01")).to eql("2023-08-05")
    end
    it "should convert amount" do
        expect(Bradesco::Creditcard.convert_amount("10,00")).to eql("10.00")
        expect(Bradesco::Creditcard.convert_amount("10.000,00")).to eql("10000.00")
    end
    it "should identify installments" do
        expect(Bradesco::Creditcard.is_installment?("SOMETHING 1/12")).to eql(true)
        expect(Bradesco::Creditcard.is_installment?("SOMETHING")).to eql(false)
        expect(Bradesco::Creditcard.is_installment?("SOMETHING 10/12")).to eql(true)
    end
    it "should return adjusted installment date" do
        expect(Bradesco::Creditcard.adjusted_installment_date(["2024-01-05",nil,"Something 1/12"])).to eql("2024-01-05")
        expect(Bradesco::Creditcard.adjusted_installment_date(["2024-01-05",nil,"Something 2/12"])).to eql("2024-02-05")
        expect(Bradesco::Creditcard.adjusted_installment_date(["2024-06-05",nil,"Something 12/12"])).to eql("2025-05-05")
    end
    it "should cleantup installment title" do
        expect(Bradesco::Creditcard.cleanup_installment_title("PARC=102 SOMETHING WEIRD")).to eql("Something Weird")
        expect(Bradesco::Creditcard.cleanup_installment_title("Parc=102 SOMETHING WEIRD")).to eql("Something Weird")
        expect(Bradesco::Creditcard.cleanup_installment_title("PARC=110 SOMETHING WEIRD")).to eql("Something Weird")
    end
    it "should convert raw csv to filtered" do
        raw_csv = ["Something","PEDRO K AXELRUD ;;; 9846","Data;Hist�rico;Valor(US$);Valor(R$);","22/11;PAYPAL *HTCLICK 8/12;0,00;815,00","30/11;AGENCIA DE VIAGENS 8/10;0,00;3844,93","","PEDRO K AXELRUD ;;; 1770","Data;Hist�rico;Valor(US$);Valor(R$);","20/08;ANUIDADE DIFERENCIADA 1/12;0,00;154,00","09/08;CUSTO TRANS. EXTERIOR-IOF ;0,00;30,48"]
        processed_csv = [["date","code","title","amount"],["2024-06-22", "8b1055a9b633643f918df4d57442a57e", "Paypal *htclick 8/12", "815.00"], ["2024-06-30", "3ece627bdf9fe8b0abbcd709ae3a635b", "Agencia De Viagens 8/10", "3844.93"], ["2023-08-20", "96f4b662bf9f910cdd809e27242fa18b", "Anuidade Diferenciada 1/12", "154.00"], ["2023-08-09", "1e2b7ce32e3ce64ea1181011fd9a7e5f", "Custo Trans. Exterior-iof", "30.48"]]
        expect(Bradesco::Creditcard.preprocess(raw_csv,"2024-08-01")).to eql(processed_csv)
    end
end

describe Itau::Account do        
    it "should convert date" do
        expect(Itau::Account.convert_date("30/07/2024")).to eql("2024-07-30")
    end

    it "should convert amount" do
        expect(Itau::Account.convert_amount("-2000,00")).to eql("-2000.00")
    end

    it "should preprocess the csv" do
        raw_csv = [["01/07/2024","TED D INT61badea1","-20000,00"]]
        processed_csv = [["date","code","title","amount"],["2024-07-01", "9c3b065b17e22ea1c36d667b3f08c58a", "Ted d Int61badea1", "-20000.00"]]
        expect(Itau::Account.preprocess(raw_csv)).to eql(processed_csv)
    end
end

describe Nubank::Account do

    it "should cleanup descriptions" do
        expect(Nubank::Account.description_cleanup("Transferência enviada pelo Pix - ADAUTO DE SOUZA SPINDOLA - •••.364.908-•• - ITAÚ UNIBANCO S.A. Agência: 152 Conta: 7165-0")).to eql("Transferência ADAUTO DE SOUZA SPINDOLA")
        expect(Nubank::Account.description_cleanup("Pagamento de boleto efetuado - Banco Bradesco SA")).to eql("Boleto Banco Bradesco SA")
        expect(Nubank::Account.description_cleanup("Something else")).to eql("Something else")
    end

    it "should preprocess file" do
        input_csv = [["Data","Valor","Identificador","Descrição"],["15/08/2024","-2410.06","66b3d10c-18a2-4b05-b95d-dec42afb345f","Pagamento de boleto efetuado - CONDOMINIO LUGANO LOCARNO"]]
        expect(Nubank::Account.preprocess(input_csv)).to eql([["date","code","title","amount"],["15/08/2024", "-2410.06", "66b3d10c-18a2-4b05-b95d-dec42afb345f", "Boleto CONDOMINIO LUGANO LOCARNO"]])
    end

end

describe Nubank::Creditcard do
    # OLD CSV format
    it "should parse old csv format" do
        raw_csv = [["date", "category", "title", "amount"], ["2024-08-31", "bnpl_transaction_upfront_national", "Uber", "22.46"], ["2024-08-31", "serviços", "Corporate Park Estacio", "32.00"], ["2024-08-31", "restaurante", "Quincho Restaurante", "80.80"]]
        processed_csv = [["date", "code", "title", "amount"], ["2024-08-31", "30a7a027030cd2fffb3bcc2474134df5", "Uber", "22.46"], ["2024-08-31", "1a3dfaf20eb9a7fe00a0b07d3acddb6e", "Corporate Park Estacio", "32.00"], ["2024-08-31", "cd1616ef289683b78e08812cf3565bb9", "Quincho Restaurante", "80.80"]]
        expect(Nubank::Creditcard.preprocess(raw_csv)).to eql(processed_csv)
    end
    it "should parse new csv format" do
        raw_csv = [["date", "title", "amount"], ["2024-09-30", "Mp *Doacoes", "150.00"], ["2024-09-29", "Yidstudio Cafe", "9.00"], ["2024-09-29", "Adm Park", "40.00"]]
        processed_csv = [["date", "code", "title", "amount"],["2024-09-30","8b1cde34a6bbae0deda347b0a7f93e48", "Mp *Doacoes", "150.00"], ["2024-09-29","e01bec3c901e6a64cb4e16135a2fccbd", "Yidstudio Cafe", "9.00"], ["2024-09-29","b7adc8c2811736fc177dab0eb7933541", "Adm Park", "40.00"]]
        expect(Nubank::Creditcard.preprocess(raw_csv)).to eql(processed_csv)
    end
end

describe Wise::Account do
    it "should clean up the csv" do
        raw_csv = [["TransferWise ID", "Date", "Amount", "Currency", "Description", "Payment Reference", "Running Balance", "Exchange From", "Exchange To", "Exchange Rate", "Payer Name", "Payee Name", "Payee Account Number", "Merchant", "Card Last Four Digits", "Card Holder Full Name", "Attachment", "Note", "Total fees", "Exchange To Amount"], ["CARD-1823091538", "23-09-2024", "150.00", "USD", "Transação por cartão de 942,86 USD emitida por Epicurean Atlanta ATLANTA", nil, "356.93", nil, nil, nil, nil, nil, nil, "Epicurean Atlanta ATLANTA", "5850", "Pedro Axelrud", nil, nil, "0.00", nil],["TRANSFER-1228465552", "21-09-2024", "200.00", "USD", "Dinheiro adicionado ao saldo da moeda", nil, "228.33", "BRL", "USD", "0.18147", nil, nil, nil, nil, nil, nil, nil, nil, "0.00", "200.00"],["BALANCE-2511676791", "19-09-2024", "218.03", "USD", "Converteu 196,28 EUR para 218,03 USD", nil, "1060.94", "EUR", "USD", "1.11595", nil, nil, nil, nil, nil, nil, nil, nil, "0.00", "218.03"]]
        processed_csv = [["date", "code", "title", "amount", "currency"],["2024-09-23","CARD-1823091538","Epicurean Atlanta ATLANTA","150.00","USD"],["2024-09-21","TRANSFER-1228465552","Dinheiro adicionado ao saldo da moeda","200.00","USD"],["2024-09-19","BALANCE-2511676791","Converteu 196.28 EUR para 218.03 USD","218.03","USD"]]
        expect(Wise::Account.preprocess(raw_csv)).to eql(processed_csv)
    end
    it "should remove double quotes" do
        raw_csv = [["TransferWise ID", "Date", "Amount", "Currency", "Description", "Payment Reference", "Running Balance", "Exchange From", "Exchange To", "Exchange Rate", "Payer Name", "Payee Name", "Payee Account Number", "Merchant", "Card Last Four Digits", "Card Holder Full Name", "Attachment", "Note", "Total fees", "Exchange To Amount"],["TRANSFER-1215011688", "10-09-2024", "1393.89", "USD", "Recebeu dinheiro de PEDRO KVITKO AXELRUD com a referência \"PEDRO AXELRUD\"", "PEDRO AXELRUD", "1715.94", nil, nil, nil, "PEDRO KVITKO AXELRUD", nil, nil, nil, nil, nil, nil, nil, "6.11", nil]]
        processed_csv = [["date", "code", "title", "amount", "currency"],["2024-09-10","TRANSFER-1215011688","Recebeu dinheiro de PEDRO KVITKO AXELRUD com a referência PEDRO AXELRUD","1393.89","USD"]]
        expect(Wise::Account.preprocess(raw_csv)).to eql(processed_csv)
    end
    it "should remove commas from description" do
        raw_csv = [["TransferWise ID", "Date", "Amount", "Currency", "Description", "Payment Reference", "Running Balance", "Exchange From", "Exchange To", "Exchange Rate", "Payer Name", "Payee Name", "Payee Account Number", "Merchant", "Card Last Four Digits", "Card Holder Full Name", "Attachment", "Note", "Total fees", "Exchange To Amount"],["BALANCE-2511676791", "19-09-2024", "218.03", "USD", "Converteu 196,28 EUR para 218,03 USD", nil, "1060.94", "EUR", "USD", "1.11595", nil, nil, nil, nil, nil, nil, nil, nil, "0.00", "218.03"]]
        processed_csv = [["date", "code", "title", "amount", "currency"],["2024-09-19","BALANCE-2511676791","Converteu 196.28 EUR para 218.03 USD","218.03","USD"]]
        expect(Wise::Account.preprocess(raw_csv)).to eql(processed_csv)

    end
end