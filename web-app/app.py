from flask import Flask, request, jsonify
import os
import psycopg2
import time

app = Flask(__name__)

def fibonacci(n):
    if n <= 1:
        return 0
    elif n == 2:
        return 1
    else:
        return fibonacci(n-1)+fibonacci(n-2)

def store_result(result):
    db_host = os.environ.get("DB_HOST", "localhost")
    db_port = os.environ.get("DB_PORT", "5432")
    db_user = os.environ.get("DB_USER", "postgres")
    db_name = os.environ.get("DB_NAME", "webapp")
    db_password = os.environ.get("DB_PASSWORD", "")

    conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        user=db_user,
        password=db_password,
        dbname=db_name
    )

    cur = conn.cursor()
    cur.execute("INSERT INTO results (result) VALUES (%s) RETURNING id;", (str(result),))
    conn.commit()

    inserted_id = cur.fetchone()[0]

    cur.close()
    conn.close()

    return inserted_id

@app.route("/")
def index():
    return jsonify({"message": "Hello World!"}), 200

@app.route("/calculate", methods=["GET"])
def calculate():
    api_key = os.getenv("API_KEY")
    request_api_key = request.headers.get("apikey")
    if request_api_key != api_key:
        return jsonify({"error": "Unauthorized"}), 403

    param = request.args.get("param")
    if not param or not param.isdigit():
        param = "10"

    start_time = time.time()
    result = fibonacci(int(param))
    calculation_time = time.time() - start_time

    try:
        record_id = store_result(result)
    except Exception as e:
        return jsonify({"error": "Failed to store result in database", "details": str(e)}), 500

    return jsonify({
        "result": result,
        "calculation_time": calculation_time,
        "record_id": record_id
    })

@app.route("/health")
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
