# Interact with your Jenkins CI server
#
# You need to set the following variables:
#   HUBOT_JENKINS_URL = "http://ci.example.com:8080"
#
# The following variables are optional 
#
#   For Basic Auth:
#   HUBOT_JENKINS_AUTH: for authenticating the trigger request (user:password)
#
#   For Github Based oAuth:
#   JENKINS_GITHUB_CLIENT_ID: used to authenticate jenkins as a client app with github
#   JENKINS_GITHUB_USERNAME: username used to authenticate with github, it must be allowed to access Jenkins
#   JENKINS_GITHUB_PASSWORD: for GITHUB_USERNAME
#      
#
# jenkins build <job> - builds the specified Jenkins job
# jenkins build <job> with <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
# jenkins list|jobs - lists Jenkins jobs
# jenkins status - lists Jenkins jobs or a message if all jobs are successfully build
# jenkins details of <job> - prints details on the last build of Jenkins job
#
class Auth
  constructor: (@robot, msg) ->
    @robot.brain.on 'loaded', =>
      if !@robot.brain.data.cookie
        @refresh(msg, @robot)
  cookie: -> @robot.brain.data.cookie
  refresh: (msg, robot) -> 
    console.log 'refresh with robot brain ' + robot.brain.data.cookie
    
    url = process.env.HUBOT_JENKINS_URL
    client_id = process.env.JENKINS_GITHUB_CLIENT_ID
    oauth_url = "https://github.com/login/oauth/authorize?client_id=" + client_id    
    req_code = msg.http("#{oauth_url}")

    if oauth_url
      creds = process.env.JENKINS_GITHUB_USERNAME + ":" + process.env.JENKINS_GITHUB_PASSWORD
      auth = new Buffer(creds).toString('base64')
      req_code.headers Authorization: "Basic #{auth}"
      req_code.get() (err, res, body) ->
        console.log 'retrieving code'
        if err
          console.log 'error retrieving code'
        else
          try
            location = res.headers.location
            console.log 'retrieved code, logging into jenkins at ' + location            
            if location
              req_cookie = msg.http("#{location}")
              req_cookie.get() (err1, res1, body1) ->
                console.log 'retrieving cookie'
                if err1
                  console.log 'error retrieving cookie'
                else
                  cookie = res1.headers["set-cookie"]
                  console.log 'retrieved cookie ' + cookie
                  if cookie
                    cookie = (cookie + "").split(";").shift()
                    robot.brain.data.cookie = cookie 
                  else
                    robot.brain.data.cookie = ""
            else
              console.log 'no location'
          catch error
            console.log 'Error processing stuff'
    else 
      @cache = ""
      console.log 'Jenkins is missing some config'

module.exports = (robot) ->
  robot.respond /jenkins build ([\w\.\-_]+)( with (.+))?/i, (msg) ->

    oauth = new Auth robot
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    params = msg.match[3]

    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/build"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"
    else if process.env.JENKINS_GITHUB_CLIENT_ID
      req.headers Cookie: "#{oauth.cookie()}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else if res.statusCode == 403
          oauth.refresh(msg, robot)
          msg.send "Jenkins says: Need to refresh authentication, try again in a few moments"         
        else if res.statusCode == 302
          msg.send "Build started for #{job} #{res.headers.location}"
        else
          msg.send "Jenkins says: #{body}"


  robot.respond /jenkins (list|jobs)/i, (msg) ->

    oauth = new Auth robot
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    req = msg.http("#{url}/api/json")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"
    else if process.env.JENKINS_GITHUB_CLIENT_ID
      req.headers Cookie: "#{oauth.cookie()}"      

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else if res.statusCode == 403
          oauth.refresh(msg, robot)
          msg.send "Jenkins says: Need to refresh authentication, try again in a few moments"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              state = if job.color == "red" then ":-(" else if job.color == "red_anime" then ":-/" else if job.color == "grey_anime" then ":-/" else if job.color == "blue_anime" then ":-/" else ":-)"
              response += "#{state} #{job.name} #{job.url}\n"
            msg.send response
          catch error
            msg.send error
   
            
  robot.respond /jenkins status/i, (msg) ->
    oauth = new Auth robot
    
    url = process.env.HUBOT_JENKINS_URL
    req_api = msg.http("#{url}/api/json")
    req_api.headers Cookie: "#{oauth.cookie()}"
    req_api.get() (err, res, body) ->
      response = ""
      if err
        msg.send "Jenkins says: #{err}"
      else if res.statusCode == 403
        oauth.refresh(msg, robot)
        msg.send "Jenkins says: Need to refresh authentication, try again in a few moments"
      else
        try
          content = JSON.parse(body)
          for job in content.jobs            
            if job.color == "red"
              response += ":-( #{job.name} #{job.url}\n"    
          if response == ""
            msg.send "Jenkins says: It's sunny in Cologne"
          else 
            msg.send response
        catch error
          msg.send error


  robot.respond /(jenkins details )(of )?([\w\.\-_]+)/i, (msg) ->

    oauth = new Auth robot
    url = process.env.HUBOT_JENKINS_URL
    one = msg.match[1]
    two = msg.match[2]
    three = msg.match[3]
    console.log '1: ' + one  + ' 2: ' + two + ' 3: ' + three
    job = msg.match[3]

    path = "#{url}/job/#{job}/lastBuild/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"
    else if process.env.JENKINS_GITHUB_CLIENT_ID
      req.headers Cookie: "#{oauth.cookie()}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else if res.statusCode == 404
          msg.send "Jenkins says: no job called #{job} found"          
        else if res.statusCode == 403
          oauth.refresh(msg, robot)
          msg.send "Jenkins says: Need to refresh authentication, try again in a few moments"
        else
          try
            content = JSON.parse(body)
            date = new Date(content.timestamp).toFormat("DD.MM HH24:MI")
            state = if content.result == "SUCCESS" then ":-)" else if content.result == "FAILURE" then ":-(" else ":-/"
            response += "#{state} #{content.fullDisplayName} (#{date})\n"
            response += "#{content.url}\n"                       
            msg.send response
          catch error
            msg.send error


            
    
      
	      
