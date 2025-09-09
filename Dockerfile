FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libglib2.0-0 \
    libcairo2 \
    libpango-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libjpeg-dev \
    libffi-dev \
    tesseract-ocr \
 && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools \
 && pip install --no-cache-dir -r requirements.txt

# App code
COPY . .

EXPOSE 5000
CMD ["python", "Api.py"]
