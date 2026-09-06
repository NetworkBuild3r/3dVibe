FROM ruby:3.3.6-alpine

WORKDIR /app
RUN gem install webrick -v 1.9.1 --no-document

COPY server.rb stub_proposals.rb ./

EXPOSE 8088
CMD ["ruby", "server.rb"]
