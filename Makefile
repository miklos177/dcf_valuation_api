# Makefile para DCF Valuation API
#
# Comandos útiles para desarrollo, testing y despliegue

.PHONY: help install dev test lint format clean docker-build docker-run

help: ## Mostrar esta ayuda
	@echo "Comandos disponibles:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Instalar dependencias del proyecto
	pip install -e .

install-dev: ## Instalar dependencias de desarrollo
	pip install -e ".[dev]"

dev: ## Ejecutar checks de desarrollo (lint + test)
	$(MAKE) lint
	$(MAKE) test

test: ## Ejecutar tests
	pytest tests/ -v

test-unit: ## Ejecutar tests unitarios
	pytest tests/unit/ -v

test-integration: ## Ejecutar tests de integración
	pytest tests/integration/ -v

test-api: ## Ejecutar tests de API
	pytest tests/api/ -v

lint: ## Ejecutar linting
	black --check app/ tests/
	isort --check-only app/ tests/
	flake8 app/ tests/
	mypy app/

format: ## Formatear código
	black app/ tests/
	isort app/ tests/

clean: ## Limpiar archivos generados
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	rm -rf .pytest_cache/
	rm -rf htmlcov/
	rm -rf .coverage

docker-build: ## Construir imagen Docker
	docker build -t dcf-valuation-api .

docker-run: ## Ejecutar con Docker Compose
	docker-compose up --build

docker-stop: ## Detener servicios Docker
	docker-compose down

precommit: ## Ejecutar pre-commit hooks
	pre-commit run --all-files

migrate: ## Ejecutar migraciones de base de datos
	alembic upgrade head

migrate-create: ## Crear nueva migración
	alembic revision --autogenerate -m "$(message)"

start: ## Iniciar aplicación en modo desarrollo
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

celery-worker: ## Iniciar worker de Celery
	celery -A app.core.celery_app worker --loglevel=info

celery-beat: ## Iniciar scheduler de Celery
	celery -A app.core.celery_app beat --loglevel=info 