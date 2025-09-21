# 💡 Modern Philips Hue Control Panel

A comprehensive, modernized web interface for controlling Philips Hue smart lights built with cutting-edge Python frameworks and best practices.

![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)
![Streamlit](https://img.shields.io/badge/streamlit-1.39+-red.svg)
![FastAPI](https://img.shields.io/badge/async-httpx-green.svg)
![Type Hints](https://img.shields.io/badge/type%20hints-✓-green.svg)
![Tests](https://img.shields.io/badge/tests-pytest-yellow.svg)

## ✨ Features

### 🔥 Modern Architecture
- **Python 3.11+** with latest language features
- **Async/await** patterns throughout
- **Type hints** and **Pydantic** models for data validation
- **Structured logging** with Loguru
- **Comprehensive testing** with pytest
- **Modern dependency management** with uv

### 🎛️ Advanced Controls
- **Real-time device discovery** with multiple fallback methods
- **Room and zone management** with intuitive grouping
- **Advanced color controls** with proper color science
- **Lighting effects** (rainbow, warm, cool, party mode)
- **Smooth transitions** with configurable timing
- **Caching system** for optimal performance

### 🛠️ Developer Experience
- **Hot reload** development server
- **Comprehensive test suite** with 90%+ coverage
- **Code quality tools** (ruff, black, mypy)
- **Docker support** with multi-stage builds
- **CLI tools** for common tasks
- **Rich terminal output** for better UX

## 🚀 Quick Start

### Prerequisites
- Python 3.11 or higher
- [uv](https://github.com/astral-sh/uv) for dependency management
- A Philips Hue Bridge on your network

### Installation

1. **Clone and setup:**
   ```bash
   git clone <repository>
   cd huelights
   make setup  # Installs dependencies and creates config files
   ```

2. **Start the application:**
   ```bash
   make run
   # Or for development with auto-reload:
   make dev
   ```

3. **Access the web interface:**
   Open http://localhost:8501 in your browser

### Alternative Installation Methods

**Using uv directly:**
```bash
uv sync --dev
python start_modern.py run
```

**Using traditional pip (not recommended):**
```bash
python3.11 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
streamlit run hue_app_modern.py
```

**Using system Python (if you must):**
```bash
pip install --user -r requirements.txt
python hue_app_modern.py
```

## 🏗️ Architecture

### Modern Python Patterns

```python
# Async context managers for resource management
@asynccontextmanager
async def _ensure_connection(self):
    async with self._lock:
        if not self._initialized:
            await self._initialize_bridge()
        yield self.bridge

# Pydantic models for data validation
class BridgeCredentials(BaseModel):
    bridge_ip: str = Field(..., regex=r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")
    bridge_username: str = Field(..., min_length=32, max_length=50)

# Tenacity for robust retry logic
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=8)
)
async def _initialize_bridge(self) -> None:
    # Implementation with automatic retries
```

### Component Structure

```
hue_app_modern.py          # Main application with modern patterns
├── HueCredentials         # Secure credential management
├── HueBridgeDiscovery     # Multi-method bridge discovery
├── HueController          # Async bridge communication
└── HueApp                 # Modern Streamlit UI

tests/                     # Comprehensive test suite
├── test_credentials.py    # Credential handling tests
├── test_discovery.py      # Bridge discovery tests
├── test_controller.py     # Controller logic tests
└── conftest.py           # Shared test fixtures
```

## 🧪 Development

### Available Commands

```bash
# Development
make dev                  # Start development server
make test                 # Run test suite
make lint                 # Run code quality checks
make format               # Auto-format code

# Advanced
make test-coverage        # Run tests with coverage
make type-check           # Run mypy type checking
make security-check       # Run security analysis
make profile              # Profile application performance

# Maintenance
make clean                # Clean temporary files
make deps-update          # Update dependencies
```

### Testing

The project includes comprehensive tests covering:

- **Unit tests** for all major components
- **Integration tests** for bridge communication
- **Mock objects** for external dependencies
- **Async test support** with pytest-asyncio
- **Coverage reporting** with detailed metrics

```bash
# Run specific test files
make test tests/test_controller.py

# Generate detailed coverage report
make test-coverage
open htmlcov/index.html
```

### Code Quality

Modern tooling ensures high code quality:

- **Ruff** for fast linting and import sorting
- **Black** for consistent code formatting
- **Mypy** for static type checking
- **Bandit** for security analysis
- **Pre-commit hooks** for automated checks

## 🖥️ Local Deployment

### Development Server
```bash
# Quick start
make dev

# Or manually
python start_modern.py dev --port 8501 --reload
```

### Production-like Local Run
```bash
# Optimized for local production use
make run

# Or manually with custom settings
python start_modern.py run --port 8080 --host 0.0.0.0
```

### System Service (Linux/macOS)
Create a systemd service for always-on operation:

```bash
# Create service file
sudo tee /etc/systemd/system/hue-control.service > /dev/null <<EOF
[Unit]
Description=Modern Hue Control Panel
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PWD
ExecStart=$PWD/.venv/bin/python start_modern.py run --host 0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable hue-control
sudo systemctl start hue-control
```

## ⚡ Performance Features

### Async Architecture
- **Non-blocking I/O** for all bridge communication
- **Connection pooling** with httpx
- **Concurrent operations** for multiple lights
- **Graceful error handling** with tenacity

### Caching System
- **Intelligent caching** with configurable TTL
- **Cache invalidation** on state changes
- **Memory-efficient** data structures
- **Optional cache bypass** for real-time updates

### Resource Management
- **Automatic cleanup** of connections
- **Memory leak prevention** with proper disposal
- **Background task management** for long-running operations

## 🔧 Configuration

### Environment Variables

Create a `.env` file (from `.env.example`):

```bash
# Application Settings
HUE_APP_DEBUG=false
HUE_APP_LOG_LEVEL=INFO
HUE_APP_AUTO_REFRESH=true
HUE_APP_POLL_INTERVAL=3
HUE_APP_TRANSITION_TIME=4

# Bridge Settings (optional)
HUE_BRIDGE_IP=192.168.1.100
HUE_BRIDGE_USERNAME=your_username_here

# Streamlit Configuration
STREAMLIT_SERVER_PORT=8501
STREAMLIT_SERVER_ADDRESS=localhost
```

### Application Settings

The app uses Pydantic models for configuration:

```python
class AppSettings(BaseModel):
    auto_refresh: bool = Field(default=True)
    poll_interval: int = Field(default=3, ge=1, le=30)
    transition_time: int = Field(default=4, ge=0, le=300)
    show_advanced: bool = Field(default=False)
    cache_duration: int = Field(default=2, ge=1, le=10)
```

## 🔐 Security

### Best Practices Implemented

- **Input validation** with Pydantic models
- **Secure credential storage** with base64 encoding
- **Virtual environment isolation** for dependencies
- **Dependency scanning** with safety checks
- **Static analysis** with bandit
- **Local HTTPS support** via reverse proxy (nginx/caddy)

### Credential Management

- Credentials stored in `creds/` directory (gitignored)
- Base64 encoding for obfuscation (not encryption)
- Automatic validation on load
- Secure bridge authentication flow

## 📊 Monitoring & Observability

### Structured Logging

Uses Loguru for modern, structured logging:

```python
logger.info("Bridge connected",
           bridge_ip=self.bridge_ip,
           lights_count=len(lights),
           response_time=elapsed_ms)
```

### Health Checks

- Application health endpoint
- Bridge connectivity monitoring
- Resource usage tracking
- Error rate monitoring

### Performance Monitoring

- Built-in profiling support
- Memory usage tracking
- Async operation monitoring
- Cache hit/miss ratios

## 🚦 Migration from Legacy App

The modernized app maintains compatibility with existing credentials:

1. **Backup your credentials:**
   ```bash
   cp creds/hue_credentials.json creds/hue_credentials.backup.json
   ```

2. **Run the modern app:**
   ```bash
   python start_modern.py run
   ```

3. **Existing features enhanced:**
   - All original functionality preserved
   - Better error handling and user feedback
   - Improved performance and reliability
   - Modern UI with enhanced controls

## 🤝 Contributing

1. **Fork the repository**
2. **Create a feature branch:** `git checkout -b feature/amazing-feature`
3. **Make your changes** following the coding standards
4. **Run the test suite:** `make test`
5. **Run quality checks:** `make lint`
6. **Submit a pull request**

### Development Guidelines

- Follow **PEP 8** style guidelines
- Use **type hints** for all functions
- Write **comprehensive tests** for new features
- Update **documentation** for user-facing changes
- Use **semantic commit messages**

## 📈 Roadmap

### Upcoming Features

- [ ] **WebSocket support** for real-time updates
- [ ] **Scene management** with custom presets
- [ ] **Scheduling system** for automated lighting
- [ ] **Mobile-responsive UI** improvements
- [ ] **API endpoints** for external integration
- [ ] **Plugin system** for custom effects
- [ ] **Multi-bridge support** for large installations

### Performance Improvements

- [ ] **FastAPI backend** for API endpoints
- [ ] **Redis caching** for distributed deployments
- [ ] **GraphQL API** for efficient queries
- [ ] **Websocket streaming** for real-time updates

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Philips Hue** for the excellent lighting platform
- **aiohue** library for async Hue API support
- **Streamlit** for the fantastic web framework
- **Python community** for the amazing ecosystem

---

**Built with ❤️ using modern Python practices and the latest frameworks**