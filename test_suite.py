import json
import requests
import os
import subprocess
import sys

min_date = 1199142000 # january 1, 2008

if __name__ == "__main__":
    try:
        problems = os.scandir("problems")
    except FileNotFoundError:
        print("Download https://drive.google.com/file/d/1kvFxYh2fo3bHfVj1OKKLX8YzuxswHvYg/view?usp=sharing and extract it to a directory named 'problems' in this folder.")
        sys.exit(1)

    passes = fails = 0
    for prob in sorted(problems, key=lambda x: x.name):
        # Luck / weird problems
        if prob.name in ["123", "123 Reloaded", "Error", "Inverse Quine", "Not Quine", "Palindromic Quine", "Quine", "Timeout"]: continue
        # Ruby version / float / rational trickery
        if prob.name in ["area of triangle", "0_5 broken keyboard", "Cancel fractions", "Equal Temperament", "MIDI note number to frequency", "Numloop"]: continue
        # Sisyphus's dump was unluckily case-insensitive, so these have wrong answers mixed in:
        if prob.name.lower() in ["helloworld", "christmas tree", "multiplication table"]: continue

        if sys.argv[1:] and prob.name < sys.argv[1]: continue
        if not prob.is_dir(): continue
        problem_path = os.path.join(prob, "problem.json")
        if not os.path.isdir(os.path.join(prob, "gs")): continue
        
        if not os.path.isfile(problem_path):
            print("Fetching " + prob.name)
            response = requests.get("http://golf.shinh.org/jsonp.rb?" + prob.name.replace(" ", "+"))
            with open(problem_path, 'wb') as fp: fp.write(response.content)
        try:
            with open(problem_path, 'rb') as fp:
                problem = json.loads(fp.read())
        except json.decoder.JSONDecodeError:
            continue
        
        for soln in os.scandir(os.path.join(prob, "gs")):
            date = int(soln.name.split(".")[-2])
            if date < min_date: continue
            if 1531576304 - 10000 < date < 1531576304 + 10000 and soln.name.startswith("lynn"): continue
            if problem["output"] and 1 <= os.path.getsize(soln.path):
                soln_string = open(soln.path, 'rb').read()
                if b'rand' in soln_string: continue
                if b'../s/' in soln_string: continue
                if b'#{' in soln_string: continue
                pi = problem["input"].encode("utf-8").replace(b"\r\n", b"\n")
                po = problem["output"].encode("utf-8").replace(b"\r\n", b"\n")
                soln_output = subprocess.run(["ruby", "--encoding", "ASCII-8BIT", "golfscript.rb", soln.path], input=pi, stdout=subprocess.PIPE).stdout
                if soln_output.rstrip() == po.rstrip():
                    print("\x1b[32mPASS\x1b[0m", soln.path)
                    passes += 1
                else:
                    print("\x1b[31mFAIL\x1b[0m", soln.path)
                    print(soln_output[:100], po[:100])
                    fails += 1
    print(f"{passes} passes, {fails} fails")

