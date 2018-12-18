##
# Extracts sections of a BCF markup file
# manually. If we want to extract the entire markup,
# this should be turned into a representable/xml decorator

module OpenProject::Bim::BcfXml
  class MarkupExtractor

    attr_reader :entry, :markup, :doc

    def initialize(entry)
      @markup = entry.get_input_stream.read
      @doc = Nokogiri::XML markup
    end

    def work_package_attributes
      {
        subject: title,
        description: description,
        status_id: statuses.fetch(status, statuses[:default])
      }
    end

    def title
      doc.xpath('/Markup/Topic/Title/text()').to_s
    end

    def status
      doc.xpath('/Markup/Topic/@TopicStatus').to_s
    end

    def description
      doc.xpath('/Markup/Topic/Description/text()').to_s
    end

    def viewpoints
      doc.xpath('/Markup/Viewpoints').map do |node|
        {
          uuid: node['Guid'],
          viewpoint: node.xpath('Viewpoint/text()').to_s,
          snapshot: node.xpath('Snapshot/text()').to_s
        }
      end
    end

    def comments
      doc.xpath('/Markup/Comment').map do |node|
        {
          uuid: node['Guid'],
          date: node.xpath('Date/text()').to_s,
          author: node.xpath('Author/text()').to_s,
          comment: node.xpath('Comment/text()').to_s
        }
      end
    end

    private

    def statuses
      @statuses ||= Hash[Status.pluck(:name, :id)].merge(default: Status.default)
    end
  end
end
