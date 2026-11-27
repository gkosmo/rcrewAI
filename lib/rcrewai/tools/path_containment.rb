# frozen_string_literal: true

module RCrewAI
  module Tools
    # Keeps the file tools inside one directory. #resolve returns the path the
    # operating system would reach, with every symlink and ".." already
    # followed. Tools must open that path and not the one they were given, so
    # that what was checked is what gets opened.
    #
    # It can't see hard links, and it doesn't protect against another process
    # swapping in a symlink between the check and the open.
    module PathContainment
      module_function

      # The real path for +path+ if it lies in +root+, otherwise nil. +path+
      # need not exist. A symlink that leads nowhere, or loops, is nil too.
      def resolve(path, root: Dir.pwd)
        real_root = File.realpath(root)
        real = physical_path(path.to_s)
        inside = real == real_root || real.start_with?(File.join(real_root, ''))
        inside ? real : nil
      rescue SystemCallError
        nil
      end

      # Walks +path+ a component at a time. File.expand_path would drop "dir/.."
      # as text, but when dir is a symlink the system goes to the parent of its
      # target.
      def physical_path(path)
        absolute = path.start_with?('/') ? path : File.join(Dir.pwd, path)

        absolute.split('/').reduce('/') do |real, part|
          case part
          when '', '.' then real
          when '..' then File.dirname(real)
          else
            step = File.join(real, part)
            File.symlink?(step) ? File.realpath(step) : step
          end
        end
      end
    end
  end
end
