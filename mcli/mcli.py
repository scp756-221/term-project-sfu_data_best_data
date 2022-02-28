"""
Simple command-line interface to all micro services
"""

# Standard library modules
import argparse
import cmd
import re

# Installed packages
import requests

# The services check only that we pass an authorization,
# not whether it's valid
DEFAULT_AUTH = 'Bearer A'


def parse_args():
    argp = argparse.ArgumentParser(
        'mcli',
        description='Command-line query interface to service'
        )
    argp.add_argument(
        'name',
        help="DNS name or IP address of server"
        )
    argp.add_argument(
        'port',
        type=int,
        help="Port number of server"
        )
    argp.add_argument(
        'service',
        help="Microservice name"
        )
    return argp.parse_args()


def get_url(name, port, service):
    # return "http://{}:{}/api/v1/music/".format(name, port)
    return "http://{}:{}/api/v1/{}/".format(name, port, service)


def parse_quoted_strings(arg):
    """
    Parse a line that includes UUID, words and '-, and "-quoted strings.
    This is a simple parser that can be easily thrown off by odd
    arguments, such as entries with mismatched quotes.  It's good
    enough for simple use, parsing "-quoted names with apostrophes.
    """
    # mre = re.compile(r'''(\w+)|'([^']*)'|"([^"]*)"''')
    mre = re.compile(r'''([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})|(\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*)|(\w+)|'([^']*)'|"([^"]*)"''')
    args = mre.findall(arg)
    return [''.join(a) for a in args]


class Mcli(cmd.Cmd):
    def __init__(self, args):
        self.name = args.name
        self.port = args.port
        self.service = args.service
        cmd.Cmd.__init__(self)
        self.prompt = 'mql: '
        self.intro = """
                    Command-line interface to micro services.
                    Enter 'help' for command list.
                    'Tab' character autocompletes commands.
                    """

    def do_read(self, arg):
        """
        Read a single record.

        Parameters
        ----------
        ID:  music_id or user_id (optional)
            The id of the record to read. If not specified,
            return empty list

        Examples
        --------
        song:
            read 6ecfafd0-8a35-4af6-a9e2-cbd79b3abeea
                Return 6ecfafd0-8a35-4af6-a9e2-cbd79b3abeea The Last Great American Dynasty.
        
        user:
            read b66f61e7-4fad-402f-aaad-101e3e2522d3
                Return b66f61e7-4fad-402f-aaad-101e3e2522d3 Clinton George starchild@pfunk.org.

        Notes
        -----
        Some versions of the server do not support listing
        all records and will instead return an empty list if
        no parameter is provided.
        """
        url = get_url(self.name, self.port, self.service)
        
        # Connect music service
        if self.service == "music":
            r = requests.get(
                url+arg.strip(),
                headers={'Authorization': DEFAULT_AUTH}
                )
            if r.status_code != 200:
                print("Non-successful status code:", r.status_code)
            items = r.json()
            if 'Count' not in items:
                print("0 items returned")
                return
            print("{} items returned".format(items['Count']))
            for i in items["Items"]:
                print("{}  {:20.20s} {}".format(
                    i['music_id'],
                    i['Artist'],
                    i['SongTitle']))

        # Connect user service
        elif self.service == "user":
            r = requests.get(
                url+arg.strip(),
                headers={'Authorization': DEFAULT_AUTH}
                )
            if r.status_code != 200:
                print("Non-successful status code:", r.status_code)
            items = r.json()
            if 'Count' not in items:
                print("0 items returned")
                return
            print("{} items returned".format(items['Count']))
            for i in items['Items']:
                print("{}  {} {} {}".format(
                    i['user_id'],
                    i['fname'],
                    i['lname'],
                    i["email"]))


    def do_create(self, arg):
        """
        Add a song or a user to the database.

        Parameters
        ----------
        song:
            artist: string
            title: string

        user:
            fname: string
            lname: string
            email: string

        All parameters can be quoted by either single or double quotes.

        Examples
        --------
        song:
            create 'Steely Dan'  "Everyone's Gone to the Movies"
                Quote the apostrophe with double-quotes.

            create Chumbawamba Tubthumping
                No quotes needed for single-word artist or title name.
        
        user:
            create joey trib joey@sfu.ca

        """
        url = get_url(self.name, self.port, self.service)
        args = parse_quoted_strings(arg)

        if self.service == "music":
            if len(args) != 2:
                print("Not enough args provided {}".format(len(args)))
                return

            payload = {
                'Artist': args[0],
                'SongTitle': args[1]
            }
            r = requests.post(
                url,
                json=payload,
                headers={'Authorization': DEFAULT_AUTH}
            )
            print(r.json())

        elif self.service == "user":
            if len(args) != 3:
                print("Not enough args provided {}".format(len(args)))
                return

            payload = {
                'fname': args[0],
                'lname': args[1],
                'email': args[2]
            }
            r = requests.post(
                url,
                json=payload,
                headers={'Authorization': DEFAULT_AUTH}
            )
            print(r.json())

    def do_delete(self, arg):
        """
        Delete a song or a user.

        Parameters
        ----------
        song: music_id
            The music_id of the song to delete.
        
        user: user_id
            The user_id of the user to delete

        Examples
        --------
        delete 6ecfafd0-8a35-4af6-a9e2-cbd79b3abeea
            Delete "The Last Great American Dynasty".
        
        delete b66f61e7-4fad-402f-aaad-101e3e2522d3
            Delete "George Clinton starchild@pfunk.org"

        """

        url = get_url(self.name, self.port, self.service)
        if self.service == "music":
            r = requests.delete(
                url+arg.strip(),
                headers={'Authorization': DEFAULT_AUTH}
                )
            if r.status_code != 200:
                print("Non-successful status code:", r.status_code)
        
        elif self.service == "user":
            r = requests.delete(
                url+arg.strip(),
                headers={'Authorization': DEFAULT_AUTH}
                )
            if r.status_code != 200:
                print("Non-successful status code:", r.status_code)

    def do_update(self, arg):
        """
        Update a song or a user.

        Parameters
        ----------
        song: music_id music_artist music_songtitle
            The music_id of the song to update with music_artist and music_songtitle
        
        user: user_id user_fname user_lname user_email
            The user_id of the user to update
                with user_fname, user_lname and user_email

        Examples
        --------
        update 6ecfafd0-8a35-4af6-a9e2-cbd79b3abeea artist music
            Update "The Last Great American Dynasty".
        
        update b66f61e7-4fad-402f-aaad-101e3e2522d3 first last first_last@sfu.ca 
            Update "George Clinton starchild@pfunk.org"
        """
        url = get_url(self.name, self.port, self.service)
        args = parse_quoted_strings(arg)

        if self.service == "music":
            if len(args) != 3:
                print("Not enough args provided")
                return
            payload = {
                'Artist': args[1],
                'SongTitle': args[2]
            }
            r = requests.put(
                url+args[0].strip(),
                json=payload,
                headers={'Authorization': DEFAULT_AUTH}
            )
            self.do_read(args[0])

        elif self.service == "user":
            if len(args) != 4:
                print("Not enough args provided")
                return
            payload = {
                'fname': args[1],
                'lname': args[2],
                'email': args[3]
            }
            r = requests.put(
                url+args[0].strip(),
                json=payload,
                headers={'Authorization': DEFAULT_AUTH}
            )
            self.do_read(args[0])

    def do_quit(self, arg):
        """
        Quit the program.
        """
        return True

    def do_test(self, arg):
        """
        Run a test stub on the server.
        """
        url = get_url(self.name, self.port, self.service)
        r = requests.get(
            url+'test',
            headers={'Authorization': DEFAULT_AUTH}
            )
        if r.status_code != 200:
            print("Non-successful status code:", r.status_code)

    def do_shutdown(self, arg):
        """
        Tell the server to shut down.

        NOT WORKING in current server version.
        """
        url = get_url(self.name, self.port, self.service)
        r = requests.get(
            url+'shutdown',
            headers={'Authorization': DEFAULT_AUTH}
            )
        if r.status_code != 200:
            print("Non-successful status code:", r.status_code)


if __name__ == '__main__':
    args = parse_args()
    Mcli(args).cmdloop()
