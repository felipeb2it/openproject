##
# Extracts sections of a BCF markup file
# manually. If we want to extract the entire markup,
# this should be turned into a representable/xml decorator
require_relative 'file_entry'

module OpenProject::Bim::BcfXml
  class IssueReader

    attr_reader :zip, :entry, :issue, :extractor, :project, :user, :type

    def initialize(project, zip, entry, current_user:)
      @zip = zip
      @entry = entry
      @project = project
      @user = current_user
      @issue = find_or_initialize_issue
      @extractor = MarkupExtractor.new(entry)

      # TODO fixed type
      @type = ::Type.find_by(name: 'Issue')
    end

    def extract!
      issue.markup = extractor.markup

      # Viewpoints will be extended on import
      build_viewpoints

      # Synchronize with a work package
      synchronize_with_work_package

      # Comments will be extended on import
      build_comments

      issue
    end

    private

    def synchronize_with_work_package
      binding.pry
      call =
        if issue.work_package
          update_work_package
        else
          create_work_package
        end

      if call.success?
        issue.work_package = call.result
        create_comment(user, "(Updated in BCF import)")
      else
        Rails.logger.error "Failed to synchronize BCF #{issue.uuid} with work package: #{call.errors.full_messages.join("; ")}"
      end
    end

    def create_work_package
      wp = WorkPackage.new work_package_attributes

      CreateWorkPackageService
        .new(user: user)
        .call(wp, send_notifications: false)
    end

    def update_work_package
      WorkPackages::UpdateService
        .new(user: user, work_package: issue.work_package)
        .call(attributes: work_package_attributes, send_notifications: false)
    end

    def work_package_attributes
      extractor.work_package_attributes.merge(
        project: project,
        type: type
      )
    end

    ##
    # Extend comments with new or updated values from XML
    def build_comments
      extractor.comments.each do |comment|
        next if issue.comments.has_uuid?(comment[:uuid])
        comment = issue.comments.build comment.merge(issue: issue)

        # Cannot link to a journal when no work package
        next if issue.work_package.nil?
        author = get_comment_author(comment)
        call = create_comment(author, comment[:comment])

        if call.success?
          comment.journal = call.result
        else
          Rails.logger.error "Failed to create comment for BCF #{issue.uuid}: #{call.errors.full_messages.join("; ")}"
        end
      end
    end

    ##
    # Try to find an author with the given mail address
    def get_comment_author(comment)
      author = project.users.find_by(mail: comment[:author])

      # If none found, use the current user
      return user if author.nil?

      # If found, check if the author can comment
      return user unless author.allowed_to?(:add_work_package_notes, project)

      author
    end

    def create_comment(author, content)
      ::AddWorkPackageNoteService
        .new(user: author, work_package: issue.work_package)
        .call(content)
    end

    ##
    # Extract viewpoints from XML
    def build_viewpoints
      extractor.viewpoints.each do |vp|
        next if issue.viewpoints.has_uuid?(vp[:uuid])

        issue.viewpoints.build(
          issue: issue,
          uuid: vp[:uuid],

          # Save the viewpoint as XML
          viewpoint: read_entry(vp[:viewpoint]),
          viewpoint_name: vp[:viewpoint],

          # Save the snapshot as file attachment
          snapshot: as_file_entry(vp[:snapshot])
        )
      end
    end

    ##
    # Find existing issue or create new
    def find_or_initialize_issue
      ::Bim::BcfIssue.find_or_initialize_by(uuid: topic_uuid, project_id: project.id)
    end

    ##
    # Get the topic name of an entry
    def topic_uuid
      entry.name.split('/').first
    end

    ##
    # Get an entry within the uuid
    def as_file_entry(filename)
      entry = zip.find_entry [topic_uuid, filename].join('/')

      if entry
        FileEntry.new(entry.get_input_stream, filename: filename)
      end
    end

    ##
    # Read an entry as string
    def read_entry(filename)
      entry = zip.find_entry [topic_uuid, filename].join('/')
      entry.get_input_stream.read
    end
  end
end
