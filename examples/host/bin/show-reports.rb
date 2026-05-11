# Loaded by `bin/rails runner` from the `dip show-reports` command —
# in a script file rather than inline because YAML + shell + Ruby +
# string interpolation in one quoted string is asking for trouble.

reports = RbRunErrorReporter::ErrorReport.recent.limit(5)
if reports.empty?
  puts "(no reports yet — hit `dip boom` first)"
else
  reports.each do |r|
    puts "[#{r.source_app || '?'}] #{r.exception_class}: #{r.message} (#{r.occurred_at})"
  end
end
