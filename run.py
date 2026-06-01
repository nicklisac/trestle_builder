from pieces import INVENTORY
from solver import Solver
from render import render_readable
import random
import json


def main():
    print("Tressel Track Builder")
    print("=" * 40)

    while True:
        seed_input = input("\nSeed (enter = random, 'q' = quit): ").strip()
        if seed_input.lower() == 'q':
            break
        if seed_input == '':
            seed = random.randint(0, 999999)
        else:
            seed = int(seed_input)

        print(f"\nSolving with seed {seed}...")
        solver = Solver(INVENTORY, timeout_sec=30.0, max_towers=100, seed=seed)
        result = solver.solve()

        if not result:
            print("No solution found. Try another seed.")
            continue

        render_readable(result)

        action = input("\n(s)ave JSON, (r)ender again, (q)uit: ").strip().lower()
        if action == 's':
            out = solver.solve_dict()
            fname = f"track_seed_{seed}.json"
            with open(fname, 'w') as f:
                json.dump(out, f, indent=2)
            print(f"Saved to {fname}")


if __name__ == "__main__":
    main()
