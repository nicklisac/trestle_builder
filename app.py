from flask import Flask, render_template, request, jsonify
from pieces import INVENTORY
from solver import Solver

app = Flask(__name__)


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/solve')
def solve():
    seed = request.args.get('seed', type=int)
    max_towers = request.args.get('max_towers', 100, type=int)
    timeout = request.args.get('timeout', 30, type=int)

    solver = Solver(INVENTORY, timeout_sec=timeout, max_towers=max_towers, seed=seed)
    result = solver.solve_dict()
    return jsonify(result)


if __name__ == '__main__':
    app.run(debug=False, port=5000)
