import logging
import os
import sys

# Installed packages
from flask import Blueprint
from flask import Flask
from flask import request
from flask import Response

from prometheus_flask_exporter import PrometheusMetrics

import requests

import simplejson as json

app = Flask(__name__)

metrics = PrometheusMetrics(app)
metrics.info('app_info', 'Music process')

db = {
    "name": "http://cmpt756db:30002/api/v1/datastore",
    "endpoint": [
        "read",
        "write",
        "delete",
        "update"
    ]
}
bp = Blueprint('app', __name__)


@bp.route('/hello', methods=['GET'])
@metrics.do_not_track()
def hello_world():
    return ("If you are reading this in a browser, your service is "
            "operational. Switch to curl/Postman/etc to interact using the "
            "other HTTP verbs.")


@bp.route('/health')
@metrics.do_not_track()
def health():
    return Response("", status=200, mimetype="application/json")


@bp.route('/readiness')
@metrics.do_not_track()
def readiness():
    return Response("", status=200, mimetype="application/json")


@bp.route('/', methods=['GET'])
def list_all():
    headers = request.headers
    # check header here
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')

    return {}


@bp.route('/', methods=['POST'])
def create_playlist():
    headers = request.headers

    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')
    
    try:
        content = request.get_json()
        music_str = content['music_list']
        music_list = music_str.strip().split(",")

    except Exception:
        return json.dumps({"message": "error reading arguments"})

    for music_id in music_list:
        music_get = requests.get(
            db['name'] + '/' + db['endpoint'][0],
            params={"objtype": "music", "objkey": music_id},
            headers={'Authorization': "test"}
        )
        if music_get.json()['Count'] == 0:
            return Response(json.dumps({"error": f"music_id {music_id} not find"}),
                status=401,
                mimetype='application/json')
        

    payload = {"objtype": "playlist", "music_list": music_list}
    url = db['name'] + '/' + db['endpoint'][1]
    response = requests.post(
        url,
        json=payload,
        headers={'Authorization': headers['Authorization']})

    return (response.json())


@bp.route('/<playlist_id>', methods=['GET'])
def get_playlist(playlist_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')
    
    payload = {"objtype": "playlist", "objkey": playlist_id}
    url = db['name'] + '/' + db['endpoint'][0]
    response = requests.get(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})
    return (response.json())


@bp.route('/<playlist_id>/add/<music_id>', methods=['PUT'])
def addmusic_playlist(playlist_id, music_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')

    payload = {"objtype": "playlist", "objkey": playlist_id}
    url = db['name'] + '/' + db['endpoint'][0]
    playlist_res = requests.get(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})

    playlist_json = playlist_res.json()

    if (playlist_json['Count'] == 0) | (playlist_json == {}):
        return Response(json.dumps({"error": f"playlist_id {playlist_id} not find"}),
                status=401,
                mimetype='application/json')
    
    playlist = playlist_json["Items"][0]
    music_list = playlist["music_list"]

    new_music_res = requests.get(
            db['name'] + '/' + db['endpoint'][0],
            params={"objtype": "music", "objkey": music_id},
            headers={'Authorization': headers['Authorization']}
    )

    if new_music_res.json()['Count'] == 0:
        return Response(json.dumps({"error": f"music_id {music_id} not find"}),
            status=401,
            mimetype='application/json')

    if music_id in music_list:
        return Response(json.dumps({"error": f"music_id {music_id} already exist " + \
                                    f"in playlist {playlist_id}"}),
                        status=401,
                        mimetype='application/json')

    music_list.append(music_id)
    payload = {
        "objtype": "playlist", 
        "objkey": playlist_id
    }
    url = db['name'] + '/' + db['endpoint'][3]
    response = requests.put(
        url,
        params=payload,
        json={"music_list": music_list})

    return (response.json())


@bp.route('/<playlist_id>/remove/<music_id>', methods=['PUT'])
def removemusic_playlist(playlist_id, music_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')

    payload = {"objtype": "playlist", "objkey": playlist_id}
    url = db['name'] + '/' + db['endpoint'][0]
    playlist_res = requests.get(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})

    playlist_json = playlist_res.json()

    if (playlist_json['Count'] == 0) | (playlist_json == {}):
        return Response(json.dumps({"error": f"playlist_id {playlist_id} not find"}),
                status=401,
                mimetype='application/json')
    
    playlist = playlist_json["Items"][0]
    music_list = playlist["music_list"]

    new_music_res = requests.get(
            db['name'] + '/' + db['endpoint'][0],
            params={"objtype": "music", "objkey": music_id},
            headers={'Authorization': headers['Authorization']}
    )

    if new_music_res.json()['Count'] == 0:
        return Response(json.dumps({"error": f"music_id {music_id} not find"}),
            status=401,
            mimetype='application/json')

    if music_id not in music_list:
        return Response(json.dumps({"error": f"music_id {music_id} does not exist " + \
                                    f"in playlist {playlist_id}"}),
                        status=401,
                        mimetype='application/json')

    music_list.remove(music_id)

    payload = {
        "objtype": "playlist", 
        "objkey": playlist_id
    }
    url = db['name'] + '/' + db['endpoint'][3]
    response = requests.put(
        url,
        params=payload,
        json={"music_list": music_list})

    return (response.json())


@bp.route('/<playlist_id>', methods=['DELETE'])
def delete_playlist(playlist_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')
    
    payload = {"objtype": "playlist", "objkey": playlist_id}
    url = db['name'] + '/' + db['endpoint'][2]
    response = requests.delete(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})
    return (response.json())


app.register_blueprint(bp, url_prefix='/api/v1/playlist/')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        logging.error("missing port arg 1")
        sys.exit(-1)

    p = int(sys.argv[1])
    # Do not set debug=True---that will disable the Prometheus metrics
    app.run(host='0.0.0.0', port=p, threaded=True)
