/bin/rm -vrf public/images/*
/bin/rm -vf data/db/*.sqlite3

bundle exec rake db:create
bundle exec rake db:migrate
bundle exec ruby test.rb
