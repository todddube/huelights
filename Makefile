# Modern Hue Control Panel - Development Makefile

.PHONY: help install run dev test lint format clean setup docker-build docker-run

# Default target
help: ## Show this help message
	@echo "Modern Hue Control Panel - Development Commands"
	@echo "================================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Installation and Setup
install: ## Install all dependencies using uv
	@echo "📦 Installing dependencies..."
	uv sync --dev
	@echo "✅ Dependencies installed successfully!"

setup: install ## Complete project setup
	@echo "🔧 Setting up project..."
	cp .env.example .env
	mkdir -p logs creds
	@echo "✅ Project setup complete!"

# Development
run: ## Run the application
	@echo "🚀 Starting Modern Hue Control Panel..."
	python start_modern.py run

dev: ## Run in development mode with auto-reload
	@echo "🔧 Starting development server..."
	python start_modern.py dev

# Testing
test: ## Run the test suite
	@echo "🧪 Running tests..."
	python start_modern.py test

test-verbose: ## Run tests with verbose output
	@echo "🧪 Running tests (verbose)..."
	python start_modern.py test --verbose

test-coverage: ## Run tests with coverage report
	@echo "🧪 Running tests with coverage..."
	python start_modern.py test --coverage
	@echo "📊 Coverage report available in htmlcov/"

# Code Quality
lint: ## Run code linting
	@echo "🔍 Running linters..."
	python start_modern.py lint

format: ## Format code automatically
	@echo "🎨 Formatting code..."
	python start_modern.py lint --fix

type-check: ## Run type checking with mypy
	@echo "🔍 Running type checks..."
	uv run mypy hue_app_modern.py --strict

# Maintenance
clean: ## Clean up temporary files and caches
	@echo "🧹 Cleaning up..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "htmlcov" -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	find . -name ".coverage" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete!"

logs-clean: ## Clean log files
	@echo "🗑️  Cleaning logs..."
	rm -rf logs/*
	@echo "✅ Logs cleaned!"

# Virtual Environment Management
venv: ## Create virtual environment
	@echo "🐍 Creating virtual environment..."
	python3.11 -m venv .venv
	@echo "✅ Virtual environment created! Activate with: source .venv/bin/activate"

venv-clean: ## Remove virtual environment
	@echo "🗑️  Removing virtual environment..."
	rm -rf .venv
	@echo "✅ Virtual environment removed!"

# Production
prod-install: ## Install production dependencies only
	@echo "📦 Installing production dependencies..."
	uv sync --no-dev

# Information and Diagnostics
info: ## Show application and environment info
	@echo "ℹ️  Application Information"
	@echo "=========================="
	python start_modern.py info

check-bridge: ## Test connection to Hue bridge
	@echo "🔍 Testing Bridge Connection"
	@echo "=========================="
	python start_modern.py check-bridge

deps-update: ## Update all dependencies
	@echo "🔄 Updating dependencies..."
	uv lock --upgrade
	@echo "✅ Dependencies updated!"

# Security
security-check: ## Run security checks
	@echo "🔒 Running security checks..."
	uv run bandit -r . -f json -o security-report.json || true
	@echo "📄 Security report saved to security-report.json"

# Performance
profile: ## Profile the application
	@echo "⚡ Profiling application..."
	uv run py-spy record -o profile.svg -- python -m streamlit run hue_app_modern.py --server.headless true &
	sleep 30
	pkill -f "streamlit run"
	@echo "📊 Profile saved to profile.svg"

# Documentation
docs-serve: ## Serve documentation locally
	@echo "📚 Serving documentation..."
	@echo "📖 Documentation would be served here (implement with mkdocs or sphinx)"

# System Service Management
service-linux: ## Create Linux systemd service
	@echo "🐧 Creating Linux service..."
	./scripts/create_linux_service.sh

service-macos: ## Create macOS LaunchAgent service
	@echo "🍎 Creating macOS service..."
	./scripts/create_macos_service.sh

service-windows: ## Create Windows Task Scheduler service
	@echo "🪟 Creating Windows service..."
	./scripts/create_windows_service.bat

# Quick development workflow
quick-test: lint test ## Run quick development checks (lint + test)

full-check: clean lint test type-check ## Run comprehensive code quality checks

# Release preparation
pre-commit: format lint test ## Run pre-commit checks
	@echo "✅ Pre-commit checks passed!"

release-check: clean full-check security-check ## Full release validation
	@echo "🚀 Release checks complete!"