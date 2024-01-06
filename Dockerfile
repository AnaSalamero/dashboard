# syntax=docker/dockerfile:1

FROM python:3

WORKDIR /app

COPY requirements.txt requirements.txt

RUN pip3 install -r requirements.txt

COPY app /app

CMD ["flask", "--app", "dashboard_app", "run", "--host=0.0.0.0", "--port", "5000"]
