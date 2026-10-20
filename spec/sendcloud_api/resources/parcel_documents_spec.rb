# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::ParcelDocuments do
  let(:png) { "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\xFF".b }

  it "fetches a PNG label as bytes through the Accept header" do
    client = serve(:get, "parcels/729017591/documents/label", body: png, content_type: "image/png")
    response = client.parcel_documents.retrieve(parcel_id: 729017591, type: "label", format: :png, dpi: 300)

    expect(request.request_headers["Accept"]).to eq("image/png")
    expect(request.params).to eq("dpi" => "300")
    expect(response.body).to eq(png)
    expect(response.body.encoding).to eq(Encoding::BINARY)
    expect(response.content_type).to eq("image/png")
  end

  it "fetches a PDF with a paper size" do
    pdf = "%PDF-1.3\n%\xE2\xE3\n".b
    client = serve(:get, "parcels/1/documents/customs-declaration", body: pdf, content_type: "application/pdf")
    response = client.parcel_documents.retrieve(parcel_id: 1, type: "customs-declaration", format: :pdf, paper_size: "A4")

    expect(request.request_headers["Accept"]).to eq("application/pdf")
    expect(request.params).to eq("paper_size" => "A4")
    expect(response.body).to eq(pdf)
  end

  it "raises a definite ParseError for a carrier-native ZPL label, which a ZPL request then returns" do
    zpl = "^XA^FO50,50^FDLabel^FS^XZ"
    client = serve(:get, "parcels/1/documents/label", body: zpl, content_type: "application/zpl")

    expect { client.parcel_documents.retrieve(parcel_id: 1, type: "label", format: :png) }
      .to raise_error(SendcloudAPI::ParseError, "Sendcloud returned application/zpl instead of image/png") { |error|
        expect(error).not_to be_ambiguous
        expect(error.response.content_type).to eq("application/zpl")
      }

    expect(client.parcel_documents.retrieve(parcel_id: 1, type: "label", format: :zpl).body).to eq(zpl.b)
  end

  it "raises the typed HTTP error for a missing parcel" do
    client = serve(:get, "parcels/1/documents/label", status: 404, body: fixture("parcel_not_found.json"))

    expect { client.parcel_documents.retrieve(parcel_id: 1, type: "label", format: :pdf) }
      .to raise_error(SendcloudAPI::NotFoundError, "Sendcloud request failed with HTTP 404")
  end

  it "rejects unknown formats and parameters before sending" do
    expect { offline_client.parcel_documents.retrieve(parcel_id: 1, type: "label", format: "png") }
      .to raise_error(ArgumentError, "format must be one of: pdf, png, zpl")
    expect { offline_client.parcel_documents.retrieve(parcel_id: 1, type: "label", format: :png, format_type: "png") }
      .to raise_error(ArgumentError, "Unknown parameters: format_type")
    expect { offline_client.parcel_documents.retrieve(parcel_id: nil, type: "label", format: :png) }
      .to raise_error(ArgumentError, "parcel_id is required")
  end
end
