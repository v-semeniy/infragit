from flask import Flask, request, render_template_string, send_file
import pandas as pd
from docx import Document
import re
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

HTML = """
<!doctype html>
<title>Title Checker WebApp</title>
<h2>Завантажте CSV та Word (.docx) файли</h2>
<form method=post enctype=multipart/form-data>
  CSV файл: <input type=file name=csv_file accept=".csv"><br><br>
  Word файл: <input type=file name=word_file accept=".docx"><br><br>
  <input type=submit value="Перевірити ID" style="background-color:lightblue;">
</form>
{% if result %}
  <h3>Результат:</h3>
  {% if missing %}
    <b>Не знайдено ID у Word:</b><br>
    <pre>{{ result }}</pre>
    <a href="{{ url_for('download_missing', filename=missing_file) }}">🔽 Завантажити missing_ids.txt</a>
  {% else %}
    <b>Усі ID знайдено у Word-файлі.</b>
  {% endif %}
{% endif %}
"""

def extract_full_text(doc):
    text = [p.text for p in doc.paragraphs]
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                text.append(cell.text)
    full_text = " ".join(text).lower()
    full_text = re.sub(r'\s+', ' ', full_text)
    return full_text

@app.route('/', methods=['GET', 'POST'])
def index():
    return "Hello world v3"

@app.route('/download/<filename>')
def download_missing(filename):
    path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    return send_file(path, as_attachment=True)

@app.route('/health')
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8501)
