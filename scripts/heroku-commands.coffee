# Description:
#   Exposes Heroku commands to hubot
#
# Dependencies:
#   "heroku-client": "^1.9.0"
#   "hubot-auth": "^1.2.0"
#
# Configuration:
#   HUBOT_HEROKU_API_KEY
#
# Commands:
#   hubot heroku info <app> - Returns useful information about the app
#   hubot heroku dynos <app> - Lists all dynos and their status
#   hubot heroku releases <app> - Latest 10 releases
#   hubot heroku rollback <app> <version> - Rollback to a release
#   hubot heroku restart <app> <dyno> - Restarts the specified app or dyno/s (e.g. worker or web.2)
#   hubot heroku migrate <app> - Runs migrations. Remember to restart the app =)
#
Heroku = require('heroku-client')
heroku = new Heroku(token: process.env.HUBOT_HEROKU_API_KEY)
_      = require('lodash')
mapper = require('../heroku-response-mapper')
moment = require('moment')
useAuth = 'false'

module.exports = (robot) ->
  auth = (msg, appName) ->
    return true

  respondToUser = (robotMessage, error, successMessage) ->
    if error
      robotMessage.reply "Shucks. An error occurred. #{error.statusCode} - #{error.body.message}"
    else
      robotMessage.reply successMessage

  rpad = (string, width, padding = ' ') ->
    if (width <= string.length) then string else rpad(width, string + padding, padding)

  objectToMessage = (object) ->
    output = []
    maxLength = 0
    keys = Object.keys(object)
    keys.forEach (key) ->
      maxLength = key.length if key.length > maxLength

    keys.forEach (key) ->
      output.push "#{rpad(key, maxLength)} : #{object[key]}"

    output.join("\n")

  # App Info
  robot.respond /heroku info (.*)/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Getting information about #{appName}"

    heroku.apps(appName).info (error, info) ->
      respondToUser(msg, error, "\n" + objectToMessage(mapper.info(info)))

  # Dynos
  robot.respond /heroku dynos (.*)/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Getting dynos of #{appName}"

    heroku.apps(appName).dynos().list (error, dynos) ->
      output = []
      if dynos
        output.push "Dynos of #{appName}"
        lastFormation = ""

        for dyno in dynos
          currentFormation = "#{dyno.type}.#{dyno.size}"

          unless currentFormation is lastFormation
            output.push "" if lastFormation
            output.push "=== #{dyno.type} (#{dyno.size}): `#{dyno.command}`"
            lastFormation = currentFormation

          updatedAt = moment(dyno.updated_at)
          updatedTime = updatedAt.utc().format('YYYY/MM/DD HH:mm:ss')
          timeAgo = updatedAt.fromNow()
          output.push "#{dyno.name}: #{dyno.state} #{updatedTime} (~ #{timeAgo})"

      respondToUser(msg, error, output.join("\n"))

  # Releases
  robot.respond /heroku releases (.*)$/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Getting releases for #{appName}"

    heroku.apps(appName).releases().list (error, releases) ->
      output = []
      if releases
        output.push "Recent releases of #{appName}"

        for release in releases.sort((a, b) -> b.version - a.version)[0..9]
          output.push "v#{release.version} - #{release.description} - #{release.user.email} -  #{release.created_at}"

      respondToUser(msg, error, output.join("\n"))

  # Rollback
  robot.respond /heroku rollback (.*) (.*)$/i, (msg) ->
    appName = msg.match[1]
    version = msg.match[2]

    return unless auth(msg, appName)

    if version.match(/v\d+$/)
      msg.reply "Telling Heroku to rollback to #{version}"

      app = heroku.apps(appName)
      app.releases().list (error, releases) ->
        release = _.find releases, (release) ->
          "v#{release.version}" ==  version

        return msg.reply "Version #{version} not found for #{appName} :(" unless release

        app.releases().rollback release: release.id, (error, release) ->
          respondToUser(msg, error, "Success! v#{release.version} -> Rollback to #{version}")

  # Restart
  robot.respond /heroku restart ([\w-]+)\s?(\w+(?:\.\d+)?)?/i, (msg) ->
    appName = msg.match[1]
    dynoName = msg.match[2]
    dynoNameText = if dynoName then ' '+dynoName else ''

    return unless auth(msg, appName)

    msg.reply "Telling Heroku to restart #{appName}#{dynoNameText}"

    unless dynoName
      heroku.apps(appName).dynos().restartAll (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}")
    else
      heroku.apps(appName).dynos(dynoName).restart (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}#{dynoNameText}")

  # Migration
  robot.respond /heroku migrate (.*)/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Telling Heroku to migrate #{appName}"

    heroku.apps(appName).dynos().create
      command: "rake db:migrate"
      attach: false
    , (error, dyno) ->
      respondToUser(msg, error, "Heroku: Running migrations for #{appName}")

      heroku.apps(appName).logSessions().create
        dyno: dyno.name
        tail: true
      , (error, session) ->
        respondToUser(msg, error, "View logs at: #{session.logplex_url}")

