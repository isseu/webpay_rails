module WebpayRails
  module Verifier
    extend ActiveSupport::Concern

    module ClassMethods
      def verify(document, cert)
        document = Nokogiri::XML(document.to_s, &:noblanks)
        signed_info_node = document.at_xpath('/soap:Envelope/soap:Header/wsse:Security/ds:Signature/ds:SignedInfo', {
          ds: 'http://www.w3.org/2000/09/xmldsig#',
          wsse: 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd',
          soap: 'http://schemas.xmlsoap.org/soap/envelope/'
        })

        # check that digest match
        check_digest(document, signed_info_node) && check_signature(document, signed_info_node, cert)
      end

    protected

      def check_digest(doc, signed_info_node)
        signed_info_node.xpath("//ds:Reference", ds: 'http://www.w3.org/2000/09/xmldsig#').each do |node|
          return false if !process_ref_node(doc, node)
        end

        true
      end

      def check_signature(doc, signed_info_node, cert)
        signed_info_canon = canonicalize(signed_info_node, ['soap'])
        signature = doc.at_xpath('//wsse:Security/ds:Signature/ds:SignatureValue', {
          ds: 'http://www.w3.org/2000/09/xmldsig#',
          wsse: 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd'
        }).text

        cert.public_key.verify(OpenSSL::Digest::SHA1.new, Base64.decode64(signature), signed_info_canon)
      end

      def digest(message)
        OpenSSL::Digest::SHA1.new.reset.digest(message)
      end

      def process_ref_node(doc, node)
        uri = node.attr('URI')
        element = doc.at_xpath("//*[@wsu:Id='#{uri[1..-1]}']", wsu: 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd')
        target = canonicalize(element, nil)
        my_digest_value = Base64.encode64(digest(target)).strip
        digest_value = node.at_xpath('//ds:DigestValue', ds: 'http://www.w3.org/2000/09/xmldsig#').text

        my_digest_value == digest_value
      end

      def canonicalize(node = document, inclusive_namespaces=nil)
        # The last argument should be exactly +nil+ to remove comments from result
        node.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, inclusive_namespaces, nil)
      end
    end
  end
end
