#!/usr/bin/env python3
"""Modern startup script for Hue Control Panel."""

import os
import subprocess
import sys
from pathlib import Path

import typer
from dotenv import load_dotenv
from loguru import logger
from rich.console import Console
from rich.panel import Panel

app = typer.Typer(help="Modern Philips Hue Control Panel")
console = Console()


def setup_environment() -> None:
    """Setup environment variables and logging."""
    # Load environment variables
    env_file = Path(".env")
    if env_file.exists():
        load_dotenv(env_file)
        console.print("✅ Loaded environment from .env file")
    else:
        console.print("ℹ️  No .env file found, using defaults")

    # Setup logging
    log_level = os.getenv("HUE_APP_LOG_LEVEL", "INFO")
    logger.remove()  # Remove default handler
    logger.add(
        sys.stdout,
        level=log_level,
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> | {message}"
    )


def check_dependencies() -> bool:
    """Check if all required dependencies are installed."""
    try:
        import streamlit
        import httpx
        import loguru
        import pydantic
        import aiohue
        console.print("✅ All dependencies are installed")
        return True
    except ImportError as e:
        console.print(f"❌ Missing dependency: {e}")
        console.print("Run: uv sync")
        return False


@app.command()
def run(
    port: int = typer.Option(8501, help="Port to run the application on"),
    host: str = typer.Option("localhost", help="Host to bind to"),
    debug: bool = typer.Option(False, help="Enable debug mode"),
    open_browser: bool = typer.Option(True, help="Open browser automatically"),
) -> None:
    """Run the modern Hue control panel."""
    console.print(
        Panel.fit(
            "🚀 Modern Philips Hue Control Panel\n"
            "Powered by Python 3.11+ and modern frameworks",
            title="Starting Application",
            border_style="green"
        )
    )

    setup_environment()

    if not check_dependencies():
        raise typer.Exit(1)

    # Build streamlit command
    cmd = [
        sys.executable, "-m", "streamlit", "run",
        "hue_app_modern.py",
        "--server.port", str(port),
        "--server.address", host,
        "--browser.gatherUsageStats", "false",
    ]

    if not open_browser:
        cmd.extend(["--server.headless", "true"])

    if debug:
        cmd.extend(["--logger.level", "debug"])

    console.print(f"🌐 Starting server at http://{host}:{port}")
    console.print("📝 Check logs directory for detailed application logs")

    try:
        subprocess.run(cmd, check=True)
    except KeyboardInterrupt:
        console.print("\n👋 Application stopped by user")
    except subprocess.CalledProcessError as e:
        console.print(f"❌ Application failed to start: {e}")
        raise typer.Exit(1)


@app.command()
def dev(
    reload: bool = typer.Option(True, help="Enable auto-reload on file changes"),
    port: int = typer.Option(8501, help="Port to run the application on"),
) -> None:
    """Run in development mode with auto-reload."""
    console.print(
        Panel.fit(
            "🔧 Development Mode\n"
            "Auto-reload enabled for rapid development",
            title="Dev Server",
            border_style="yellow"
        )
    )

    setup_environment()

    if not check_dependencies():
        raise typer.Exit(1)

    # Development command with auto-reload
    cmd = [
        sys.executable, "-m", "streamlit", "run",
        "hue_app_modern.py",
        "--server.port", str(port),
        "--server.runOnSave", str(reload).lower(),
        "--browser.gatherUsageStats", "false",
        "--logger.level", "debug",
    ]

    console.print(f"🔄 Development server starting on port {port}")
    console.print("📁 Watching for file changes...")

    try:
        subprocess.run(cmd, check=True)
    except KeyboardInterrupt:
        console.print("\n👋 Development server stopped")


@app.command()
def test(
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Verbose output"),
    coverage: bool = typer.Option(True, help="Generate coverage report"),
    file: str = typer.Option(None, help="Run specific test file"),
) -> None:
    """Run the test suite."""
    console.print(
        Panel.fit(
            "🧪 Running Test Suite\n"
            "Comprehensive testing with pytest",
            title="Tests",
            border_style="blue"
        )
    )

    if not check_dependencies():
        raise typer.Exit(1)

    cmd = [sys.executable, "-m", "pytest"]

    if verbose:
        cmd.append("-v")

    if coverage:
        cmd.extend(["--cov=.", "--cov-report=term-missing", "--cov-report=html"])

    if file:
        cmd.append(file)

    console.print("🔍 Running tests...")

    try:
        result = subprocess.run(cmd, check=False)
        if result.returncode == 0:
            console.print("✅ All tests passed!")
            if coverage:
                console.print("📊 Coverage report generated in htmlcov/")
        else:
            console.print("❌ Some tests failed")
            raise typer.Exit(1)
    except FileNotFoundError:
        console.print("❌ pytest not found. Run: uv sync --dev")
        raise typer.Exit(1)


@app.command()
def lint(
    fix: bool = typer.Option(False, help="Automatically fix issues"),
) -> None:
    """Run code linting and formatting."""
    console.print(
        Panel.fit(
            "🔍 Code Quality Check\n"
            "Running linters and formatters",
            title="Linting",
            border_style="cyan"
        )
    )

    # Run ruff for linting
    console.print("🔧 Running ruff...")
    ruff_cmd = [sys.executable, "-m", "ruff", "check", "."]
    if fix:
        ruff_cmd.append("--fix")

    try:
        subprocess.run(ruff_cmd, check=True)
        console.print("✅ Ruff checks passed")
    except (subprocess.CalledProcessError, FileNotFoundError):
        console.print("❌ Ruff issues found or not installed")

    # Run black for formatting
    if fix:
        console.print("🎨 Running black...")
        try:
            subprocess.run([sys.executable, "-m", "black", "."], check=True)
            console.print("✅ Code formatted with black")
        except (subprocess.CalledProcessError, FileNotFoundError):
            console.print("❌ Black formatting failed or not installed")

    # Run mypy for type checking
    console.print("🔍 Running mypy...")
    try:
        subprocess.run([sys.executable, "-m", "mypy", "hue_app_modern.py"], check=True)
        console.print("✅ Type checking passed")
    except (subprocess.CalledProcessError, FileNotFoundError):
        console.print("❌ Type checking issues found or mypy not installed")


@app.command()
def install() -> None:
    """Install dependencies using uv."""
    console.print(
        Panel.fit(
            "📦 Installing Dependencies\n"
            "Using uv for fast package management",
            title="Installation",
            border_style="magenta"
        )
    )

    try:
        # Install production dependencies
        console.print("📥 Installing production dependencies...")
        subprocess.run(["uv", "sync"], check=True)

        # Install development dependencies
        console.print("🔧 Installing development dependencies...")
        subprocess.run(["uv", "sync", "--dev"], check=True)

        console.print("✅ All dependencies installed successfully!")
        console.print("🚀 Run 'python start_modern.py run' to start the application")

    except subprocess.CalledProcessError:
        console.print("❌ Installation failed")
        console.print("Make sure uv is installed: https://github.com/astral-sh/uv")
        raise typer.Exit(1)
    except FileNotFoundError:
        console.print("❌ uv not found")
        console.print("Install uv first: https://github.com/astral-sh/uv")
        raise typer.Exit(1)


@app.command()
def info() -> None:
    """Show application and environment information."""
    console.print(
        Panel.fit(
            "ℹ️  Modern Hue Control Panel\n"
            "Built with modern Python frameworks and best practices",
            title="Application Info",
            border_style="blue"
        )
    )

    # Python version
    console.print(f"🐍 Python: {sys.version}")

    # Dependencies info
    try:
        import streamlit
        console.print(f"🌊 Streamlit: {streamlit.__version__}")
    except ImportError:
        console.print("🌊 Streamlit: Not installed")

    try:
        import httpx
        console.print(f"🌐 HTTPX: {httpx.__version__}")
    except ImportError:
        console.print("🌐 HTTPX: Not installed")

    try:
        import pydantic
        console.print(f"📊 Pydantic: {pydantic.__version__}")
    except ImportError:
        console.print("📊 Pydantic: Not installed")

    # Environment info
    console.print(f"📁 Working Directory: {Path.cwd()}")
    console.print(f"🔧 Environment File: {'.env exists' if Path('.env').exists() else 'Not found'}")

    # Bridge credentials info
    console.print("\n🌉 Bridge Credentials:")
    try:
        from hue_app_modern import HueCredentials
        creds = HueCredentials()
        ip, username = creds.load()
        if ip and username:
            console.print(f"   📍 Bridge IP: {ip}")
            console.print(f"   🔑 Username: {'*' * (len(username) - 8) + username[-8:]}")
            console.print("   ✅ Credentials found")
        else:
            console.print("   ❌ No credentials found")
    except Exception as e:
        console.print(f"   ❌ Error loading credentials: {e}")


@app.command()
def check_bridge() -> None:
    """Test connection to Hue bridge using stored credentials."""
    console.print(
        Panel.fit(
            "🔍 Testing Bridge Connection\n"
            "Checking connectivity to your Hue bridge",
            title="Bridge Test",
            border_style="cyan"
        )
    )

    try:
        from hue_app_modern import HueCredentials
        import asyncio

        async def test_connection():
            creds = HueCredentials()
            ip, username = creds.load()

            if not ip or not username:
                console.print("❌ No credentials found")
                return False

            console.print(f"🔍 Testing connection to bridge at {ip}...")
            result = await creds.is_valid_async()
            return result

        result = asyncio.run(test_connection())

        if result:
            console.print("✅ Bridge connection successful!")
            console.print("🚀 You can now run the application with: python start_modern.py run")
        else:
            console.print("❌ Bridge connection failed")
            console.print("💡 Possible solutions:")
            console.print("   • Check that your bridge is powered on")
            console.print("   • Verify your computer is on the same network")
            console.print("   • Try restarting your bridge")
            console.print("   • Run the app to re-authenticate if needed")

    except Exception as e:
        console.print(f"❌ Error testing bridge: {e}")


if __name__ == "__main__":
    app()