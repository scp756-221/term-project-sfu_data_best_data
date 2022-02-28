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


@bp.route('/', methods=['GET'])
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

@bp.route('/', methods=['POST'])
def create_playlist():
    headers = request.headers

    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')
    
    payload = {"objtype": "playlist", "music_list": []}
    url = db['name'] + '/' + db['endpoint'][1]
    response = requests.post(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})
    return (response.json())

@bp.route('/all_lists/<playlist_id>', methods=['GET'])
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
def add_music(playlist_id, music_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')

    playlist_res = requests.get(
        db['name'] + '/' + db['endpoint'][0],
        params={"objtype": "playlist", "objkey": playlist_id},
        headers={'Authorization': headers['Authorization']}
    )
    if not playlist_res.ok:
        return {"error": "playlist not found"}
    
    playlist = playlist_res.json()["Items"][0]
    music_list = playlist["music_list"]

    new_music_res = requests.get(
        db['name'] + '/' + db['endpoint'][0],
        params={"objtype": "music", "objkey": music_id},
        headers={'Authorization': headers['Authorization']}
    )
    if not new_music_res.ok:
        return {"error": "music not found"}
    new_music = new_music_res.json()["Items"][0]

    if new_music in music_list:
        return {"error": "music already in playlist"}

    music_list.append(new_music)
    payload = {
        "objtype": "playlist", 
        "objkey": playlist_id,
        "music_list": music_list
    }
    url = db['name'] + '/' + db['endpoint'][3]
    response = requests.put(
        url,
        params=payload,
        headers={'Authorization': headers['Authorization']})
    return (response.json())

@bp.route('/<playlist_id>/remove/<music_id>', methods=['PUT'])
def remove_music(playlist_id, music_id):
    headers = request.headers
    
    if 'Authorization' not in headers:
        return Response(json.dumps({"error": "missing auth"}),
                        status=401,
                        mimetype='application/json')
    # TODO
    return {}

@bp.route('/<playlist_id>', methods=['DELETE'])
def update_playlist(playlist_id):
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
