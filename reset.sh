/bin/rm -vrf public/images/*

bundle exec rake db:drop
bundle exec rake db:create
bundle exec rake db:migrate
