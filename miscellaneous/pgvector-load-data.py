import os
from dotenv import load_dotenv
import psycopg2
import numpy
# from langchain.embeddings import OpenAIEmbeddings
from langchain_community.embeddings import OpenAIEmbeddings, OllamaEmbeddings

# Load env vars
load_dotenv()

os.environ['OPENAI_API_KEY'] = os.getenv("OPENAI_API_KEY")
llm_model_name = os.getenv("OLLAMA_MODEL", "qwen2:latest")
sqlmonitor_inventory_server = os.getenv("SQLMONITOR_INVENTORY_SERVER", "localhost")
sqlmonitor_login_name = os.getenv("SQLMONITOR_LOGIN_NAME", "sa")
sqlmonitor_login_password = os.getenv("SQLMONITOR_LOGIN_PASSWORD")
sqlmonitor_database = os.getenv("SQLMONITOR_DATABASE", "DBA")

texts = [
    "Type: Desktop, OS: Ubuntu, GPU: NVIDIA, CPU: AMD, RAM: 64GB, SSD: 2TB",
    "Type: Desktop, OS: Linux Mint, GPU: NVIDIA, CPU: AMD, RAM: 64GB, SSD: 2TB",
    "Type: Desktop, OS: Manjaro, GPU: NVIDIA, CPU: AMD, RAM: 64GB, SSD: 2TB",
    "Type: Desktop, OS: Windows, GPU: NVIDIA, CPU: AMD, RAM: 64GB, SSD: 2TB",
    "Type: Desktop, OS: Windows, GPU: NVIDIA, CPU: Intel, RAM: 32GB, SSD: 1TB",
    "Type: Desktop, OS: Fedora, GPU: AMD, CPU: AMD, Intel: 16GB, SSD: 1TB",
    "Type: Desktop, OS: Windows, GPU: NVIDIA, CPU: AMD, RAM: 16GB, SSD: 2TB",
    "Type: Desktop, OS: Windows, GPU: AMD, CPU: AMD, RAM: 16GB, SSD: 1TB",
    "Type: Desktop, OS: Ubuntu, GPU: NVIDIA, CPU: AMD, RAM: 32GB, SSD: 1TB",
    "Type: Laptop, OS: Windows, GPU: NVIDIA, CPU: Intel, RAM: 16GB, SSD: 1TB",
    "Type: Laptop, OS: Ubuntu, GPU: AMD, CPU: AMD, RAM: 16GB, SSD: 500GB",
    "Type: Laptop, OS: Mac OS, GPU: NVIDIA, CPU: AMD, RAM: 16GB, SSD: 1TB"
]


