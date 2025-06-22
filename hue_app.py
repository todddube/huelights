import streamlit as st
from huesdk import Hue, Discover
import time
import logging
import base64
import json
import urllib3
import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, Dict, Any, Tuple, List, Union
from pathlib import Path
from datetime import datetime, timedelta
import socket
import requests

# Suppress InsecureRequestWarning
# TODO: Implement proper certificate verification
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Create logs directory if it doesn't exist
log_dir = Path('logs')
log_dir.mkdir(exist_ok=True)

# Configure logging with both file and console handlers
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_dir / 'hue_app.log'),
        logging.StreamHandler()
    ]
)

# Get logger for this module
logger = logging.getLogger(__name__)
logger.info("Hue App started " + datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

class HueCredentials:
    def __init__(self, filepath: str = 'creds/hue_credentials.json'):
        self.filepath = Path(filepath)
        self.filepath.parent.mkdir(exist_ok=True)
        
    def save(self, ip: str, username: str) -> None:
        """Save Hue bridge credentials with base64 encoding."""
        try:
            encoded_creds = {
                'bridge_ip': base64.b64encode(ip.encode()).decode('utf-8'),
                'bridge_username': base64.b64encode(username.encode()).decode('utf-8'),
                'created_at': datetime.now().isoformat(),
                'version': '2.0'
            }
            
            with open(self.filepath, 'w') as f:
                json.dump(encoded_creds, f, indent=4)
                
            logger.info(f"Credentials saved to {self.filepath}")
            
        except Exception as e:
            logger.error(f"Error saving credentials: {str(e)}")
            raise

    def load(self) -> Tuple[Optional[str], Optional[str]]:
        """Load and decode credentials from file."""
        try:
            if not self.filepath.exists():
                return None, None
                
            with open(self.filepath, 'r') as f:
                encoded_creds = json.load(f)
            
            bridge_ip = base64.b64decode(encoded_creds['bridge_ip']).decode('utf-8')
            bridge_username = base64.b64decode(encoded_creds['bridge_username']).decode('utf-8')
            
            return bridge_ip, bridge_username
            
        except Exception as e:
            logger.error(f"Error loading credentials: {str(e)}")
            return None, None

    def is_valid(self) -> bool:
        """Check if stored credentials are valid by testing connection."""
        bridge_ip, bridge_username = self.load()
        if not bridge_ip or not bridge_username:
            return False
            
        try:
            # Quick connection test
            hue = Hue(bridge_ip=bridge_ip, username=bridge_username)
            hue.get_lights()  # Test API call
            return True
        except Exception:
            return False

class HueBridgeDiscovery:
    """Enhanced bridge discovery with multiple methods."""
    
    @staticmethod
    def discover_bridges() -> List[Dict[str, str]]:
        """Discover Hue bridges using multiple methods."""
        bridges = []
        
        # Method 1: Use huesdk's discovery
        try:
            discover = Discover()
            found_bridges = discover.find_hue_bridge()
            if found_bridges:
                for bridge in found_bridges:
                    bridges.append({
                        'method': 'internet',
                        'ip': bridge.get('internalipaddress', ''),
                        'id': bridge.get('id', ''),
                        'port': str(bridge.get('port', 443))
                    })
        except Exception as e:
            logger.warning(f"Internet discovery failed: {e}")
        
        # Method 2: mDNS discovery
        try:
            discover = Discover()
            mdns_bridges = discover.find_hue_bridge_mdns(timeout=3)
            if mdns_bridges:
                for bridge in mdns_bridges:
                    bridges.append({
                        'method': 'mdns',
                        'ip': bridge.get('ip', ''),
                        'id': bridge.get('id', ''),
                        'port': str(bridge.get('port', 443))
                    })
        except Exception as e:
            logger.warning(f"mDNS discovery failed: {e}")
        
        # Method 3: Network scan (last resort)
        if not bridges:
            bridges.extend(HueBridgeDiscovery._network_scan())
        
        # Remove duplicates
        unique_bridges = []
        seen_ips = set()
        for bridge in bridges:
            if bridge['ip'] not in seen_ips:
                unique_bridges.append(bridge)
                seen_ips.add(bridge['ip'])
        
        return unique_bridges
    
    @staticmethod
    def _network_scan() -> List[Dict[str, str]]:
        """Scan local network for Hue bridges."""
        bridges = []
        try:
            # Get local IP range
            hostname = socket.gethostname()
            local_ip = socket.gethostbyname(hostname)
            network_base = '.'.join(local_ip.split('.')[:-1]) + '.'
            
            def check_ip(ip):
                try:
                    response = requests.get(f"http://{ip}/api/config", timeout=1)
                    if response.status_code == 200:
                        data = response.json()
                        if 'bridgeid' in data:
                            return {
                                'method': 'scan',
                                'ip': ip,
                                'id': data.get('bridgeid', ''),
                                'port': '80'
                            }
                except:
                    pass
                return None
            
            # Scan common IPs in parallel
            with ThreadPoolExecutor(max_workers=20) as executor:
                futures = []
                for i in range(1, 255):
                    ip = f"{network_base}{i}"
                    futures.append(executor.submit(check_ip, ip))
                
                for future in futures:
                    result = future.result()
                    if result:
                        bridges.append(result)
            
        except Exception as e:
            logger.warning(f"Network scan failed: {e}")
        
        return bridges

class HueController:
    def __init__(self, ip: str, username: str):
        self.bridge_ip = ip
        self.username = username
        self.hue = self._init_connection(ip, username)
        self._cache = {}
        self._cache_expiry = {}
        self._cache_duration = 2  # seconds
        
    @staticmethod
    @st.cache_resource
    def _init_connection(ip: str, username: str) -> Optional[Hue]:
        """Initialize Hue bridge connection."""
        try:
            return Hue(bridge_ip=ip, username=username)
        except Exception as e:
            logger.error(f"Error initializing Hue: {str(e)}")
            raise

    def _is_cache_valid(self, key: str) -> bool:
        """Check if cache entry is still valid."""
        if key not in self._cache_expiry:
            return False
        return datetime.now() < self._cache_expiry[key]

    def _set_cache(self, key: str, value: Any) -> None:
        """Set cache with expiry time."""
        self._cache[key] = value
        self._cache_expiry[key] = datetime.now() + timedelta(seconds=self._cache_duration)

    def get_lights(self) -> List:
        """Get lights with caching."""
        cache_key = "lights"
        if self._is_cache_valid(cache_key):
            return self._cache[cache_key]
        
        lights = self.hue.get_lights()
        self._set_cache(cache_key, lights)
        return lights
    
    def get_groups(self) -> List:
        """Get groups with caching."""
        cache_key = "groups"
        if self._is_cache_valid(cache_key):
            return self._cache[cache_key]
        
        groups = self.hue.get_groups()
        self._set_cache(cache_key, groups)
        return groups

    def get_bridge_info(self) -> Dict[str, Any]:
        """Get bridge information."""
        cache_key = "bridge_info"
        if self._is_cache_valid(cache_key):
            return self._cache[cache_key]
        
        try:
            response = requests.get(f"http://{self.bridge_ip}/api/{self.username}/config", timeout=3)
            if response.status_code == 200:
                info = response.json()
                self._set_cache(cache_key, info)
                return info
        except Exception as e:
            logger.error(f"Error getting bridge info: {e}")
        
        return {}
    
    @staticmethod
    def get_light_state(light) -> bool:
        """Get current light state safely."""
        try:
            return bool(light.state.get('on', False))
        except AttributeError:
            return False

    @staticmethod
    def get_light_brightness(light) -> int:
        """Get current light brightness safely (0-100%)."""
        try:
            # Hue brightness is 1-254, convert to percentage
            bri = light.state.get('bri', 0)
            if bri == 0:
                return 0
            # Convert to percentage (0-100%)
            return max(1, min(100, int((bri / 254) * 100)))
        except AttributeError:
            logger.warning(f"Light {getattr(light, 'name', 'unknown')} has no brightness attribute")
            return 0

    @staticmethod
    def get_light_color_info(light) -> Dict[str, Any]:
        """Get light color information."""
        try:
            color_info = {
                'hue': light.state.get('hue', 0),
                'sat': light.state.get('sat', 0),
                'xy': light.state.get('xy', [0, 0]),
                'ct': light.state.get('ct', 0),
                'colormode': light.state.get('colormode', 'hs')
            }
            return color_info
        except AttributeError:
            return {}

    def control_light(self, light, new_state: bool, transition: int = 4) -> bool:
        """Control individual light state with transition support."""
        try:
            if new_state:
                light.on(transition=transition)
            else:
                light.off(transition=transition)
            
            # Invalidate cache
            if "lights" in self._cache:
                del self._cache["lights"]
            
            logger.info(f"Set light {light.name} to state: {new_state}")
            return True
        except Exception as e:
            logger.error(f"Error controlling light {light.name}: {str(e)}")
            return False
    
    def set_light_brightness(self, light, brightness_pct: int, transition: int = 4) -> bool:
        """Set light brightness with transition support."""
        try:
            # Convert percentage to Hue's 1-254 range
            bri = max(1, min(254, int((brightness_pct / 100) * 254)))
            light.set_brightness(bri, transition=transition)
            
            # Invalidate cache
            if "lights" in self._cache:
                del self._cache["lights"]
            
            logger.info(f"Set light {light.name} brightness to: {brightness_pct}%")
            return True
        except Exception as e:
            logger.error(f"Error setting brightness for light {light.name}: {str(e)}")
            return False

    def set_light_color(self, light, color: Union[str, int, Tuple[float, float]], transition: int = 4) -> bool:
        """Set light color with multiple input formats."""
        try:
            if isinstance(color, str) and color.startswith('#'):
                # Hex color
                light.set_color(hexa=color, transition=transition)
            elif isinstance(color, int):
                # Hue value
                light.set_color(hue=color, transition=transition)
            elif isinstance(color, (list, tuple)) and len(color) == 2:
                # XY coordinates
                light.set_state({'xy': color}, transition=transition)
            else:
                raise ValueError(f"Unsupported color format: {color}")
            
            # Invalidate cache
            if "lights" in self._cache:
                del self._cache["lights"]
            
            logger.info(f"Set light {light.name} color to: {color}")
            return True
        except Exception as e:
            logger.error(f"Error setting color for light {light.name}: {str(e)}")
            return False

    @staticmethod
    def get_group_state(group) -> bool:
        """Get current group state safely."""
        try:
            return bool(group.state.get('any_on', False))
        except AttributeError:
            return False

    def control_group(self, group, new_state: bool, transition: int = 4) -> bool:
        """Control group state with transition support."""
        try:
            if new_state:
                group.on(transition=transition)
            else:
                group.off(transition=transition)
            
            # Invalidate caches
            for key in ["groups", "lights"]:
                if key in self._cache:
                    del self._cache[key]
            
            logger.info(f"Set group {group.name} to state: {new_state}")
            return True
        except Exception as e:
            logger.error(f"Error controlling group {group.name}: {str(e)}")
            return False

    def set_group_brightness(self, group, brightness_pct: int, transition: int = 4) -> bool:
        """Set group brightness with transition support."""
        try:
            bri = max(1, min(254, int((brightness_pct / 100) * 254)))
            group.set_brightness(bri, transition=transition)
            
            # Invalidate caches
            for key in ["groups", "lights"]:
                if key in self._cache:
                    del self._cache[key]
            
            logger.info(f"Set group {group.name} brightness to: {brightness_pct}%")
            return True
        except Exception as e:
            logger.error(f"Error setting group brightness {group.name}: {str(e)}")
            return False

    def clear_cache(self) -> None:
        """Clear all cached data."""
        self._cache.clear()
        self._cache_expiry.clear()

class HueApp:
    def __init__(self):
        self.credentials = HueCredentials()
        self.controller = None
        self.discovery = HueBridgeDiscovery()
        
        # Initialize session state variables
        if 'last_update' not in st.session_state:
            st.session_state.last_update = 0
        if 'poll_interval' not in st.session_state:
            st.session_state.poll_interval = 3  # 3 seconds default
        if 'auto_refresh' not in st.session_state:
            st.session_state.auto_refresh = True
        if 'transition_time' not in st.session_state:
            st.session_state.transition_time = 4  # 400ms default
        if 'discovered_bridges' not in st.session_state:
            st.session_state.discovered_bridges = []
        if 'show_advanced' not in st.session_state:
            st.session_state.show_advanced = False

    def should_update(self) -> bool:
        """Check if it's time to update based on polling interval"""
        if not st.session_state.auto_refresh:
            return False
            
        current_time = time.time()
        if current_time - st.session_state.last_update >= st.session_state.poll_interval:
            st.session_state.last_update = current_time
            return True
        return False

    def render_sidebar_settings(self):
        """Render sidebar with app settings."""
        with st.sidebar:
            st.header("⚙️ Settings")
            
            # Auto-refresh settings
            st.session_state.auto_refresh = st.checkbox(
                "Auto-refresh", 
                value=st.session_state.auto_refresh,
                help="Automatically refresh device states"
            )
            
            if st.session_state.auto_refresh:
                st.session_state.poll_interval = st.slider(
                    "Refresh interval (seconds)", 
                    min_value=1, 
                    max_value=10, 
                    value=st.session_state.poll_interval,
                    help="How often to refresh device states"
                )
            
            # Transition settings
            st.session_state.transition_time = st.slider(
                "Transition time (ms)", 
                min_value=0, 
                max_value=30, 
                value=st.session_state.transition_time,
                step=1,
                help="Transition time for light changes (0 = instant)"
            ) * 100  # Convert to milliseconds
            
            # Advanced settings
            st.session_state.show_advanced = st.checkbox(
                "Show advanced controls", 
                value=st.session_state.show_advanced,
                help="Show color controls and advanced options"
            )
            
            st.divider()
            
            # Bridge management
            st.subheader("🌉 Bridge Management")
            
            if st.button("🔍 Discover Bridges"):
                with st.spinner("Discovering bridges..."):
                    st.session_state.discovered_bridges = self.discovery.discover_bridges()
                st.rerun()
            
            if st.button("🔄 Clear Cache"):
                if self.controller:
                    self.controller.clear_cache()
                st.success("Cache cleared!")
            
            if st.button("❌ Clear Credentials"):
                if self.credentials.filepath.exists():
                    self.credentials.filepath.unlink()
                    st.success("Credentials cleared!")
                    st.rerun()

    def render_status_bar(self):
        """Render enhanced status bar with bridge and update information."""
        if self.controller:
            bridge_info = self.controller.get_bridge_info()
            
            col1, col2, col3, col4 = st.columns([2, 2, 2, 1])
            
            with col1:
                if bridge_info:
                    st.caption(f"🌉 Bridge: {bridge_info.get('name', 'Unknown')}")
                else:
                    st.caption(f"🌉 Bridge: {self.controller.bridge_ip}")
            
            with col2:
                if bridge_info:
                    st.caption(f"📡 API: {bridge_info.get('apiversion', 'Unknown')}")
                else:
                    st.caption("📡 API: Connected")
            
            with col3:
                if st.session_state.auto_refresh:
                    st.caption("🔄 Auto-refresh: ON")
                else:
                    st.caption("⏸️ Auto-refresh: OFF")
            
            with col4:
                st.caption(f"🕐 {datetime.now().strftime('%H:%M:%S')}")

    def show_bridge_discovery(self) -> Tuple[Optional[str], Optional[str]]:
        """Enhanced bridge discovery and setup."""
        st.warning("No valid credentials found. Let's set up your Hue Bridge:")
        
        # Discovery section
        col1, col2 = st.columns([3, 1])
        
        with col1:
            st.subheader("🔍 Discovered Bridges")
        
        with col2:
            if st.button("🔄 Refresh"):
                with st.spinner("Discovering bridges..."):
                    st.session_state.discovered_bridges = self.discovery.discover_bridges()
                st.rerun()
        
        # Show discovered bridges
        if st.session_state.discovered_bridges:
            for i, bridge in enumerate(st.session_state.discovered_bridges):
                with st.expander(f"Bridge {i+1}: {bridge['ip']} ({bridge['method']})"):
                    st.write(f"**IP Address:** {bridge['ip']}")
                    st.write(f"**Discovery Method:** {bridge['method']}")
                    st.write(f"**Bridge ID:** {bridge['id']}")
                    st.write(f"**Port:** {bridge['port']}")
                    
                    if st.button(f"Use Bridge {i+1}", key=f"use_bridge_{i}"):
                        return self.setup_bridge_credentials(bridge['ip'])
        else:
            st.info("No bridges discovered. You can manually enter bridge details below.")
        
        # Manual entry section
        st.subheader("✏️ Manual Setup")
        
        with st.form("manual_setup"):
            input_ip = st.text_input(
                "Bridge IP Address", 
                placeholder="192.168.1.xxx",
                help="You can find this at https://discovery.meethue.com/"
            )
            
            setup_method = st.radio(
                "Setup Method",
                ["🔗 Generate New Token (Recommended)", "🔑 Use Existing Token"],
                help="Generate a new token by pressing the bridge button, or enter an existing one"
            )
            
            if setup_method.startswith("🔑"):
                input_username = st.text_input("Bridge Username/Token")
            else:
                input_username = None
            
            submitted = st.form_submit_button("Setup Bridge")
            
            if submitted and input_ip:
                if setup_method.startswith("🔗"):
                    return self.setup_bridge_credentials(input_ip)
                elif input_username:
                    self.credentials.save(input_ip, input_username)
                    st.success("Credentials saved successfully!")
                    st.rerun()
        
        return None, None

    def setup_bridge_credentials(self, bridge_ip: str) -> Tuple[Optional[str], Optional[str]]:
        """Setup bridge credentials with button press method."""
        st.info("🔴 **Please press the button on your Hue Bridge now!**")
        st.write("You have 30 seconds to press the physical button on your bridge.")
        
        progress_bar = st.progress(0)
        status_text = st.empty()
        
        # Try to connect for 30 seconds
        for i in range(30):
            try:
                username = Hue.connect(bridge_ip=bridge_ip)
                if username:
                    self.credentials.save(bridge_ip, username)
                    st.success("✅ Bridge connected successfully!")
                    time.sleep(1)
                    st.rerun()
                    return bridge_ip, username
            except Exception as e:
                pass
            
            remaining = 30 - i
            status_text.text(f"Waiting for button press... {remaining} seconds remaining")
            progress_bar.progress((i + 1) / 30)
            time.sleep(1)
        st.error("❌ Connection failed. Please try again and make sure to press the bridge button.")
        return None, None

    def render_light_controls(self, light, group_id: Optional[str] = None):
        """Render enhanced light controls with color support."""
        key_prefix = f"light_{light.id_}"
        if group_id:
            key_prefix += f"_in_group_{group_id}"
        
        # Light name and status row
        lcol1, lcol2, lcol3 = st.columns([2.5, 0.5, 1])
        
        with lcol1:
            st.write(f"  💡 **{light.name}**")
        
        with lcol2:
            state_icon = "🟢" if self.controller.get_light_state(light) else "⚫"
            st.write(state_icon)
        
        with lcol3:
            current_light_state = self.controller.get_light_state(light)
            button_text = "Turn Off" if current_light_state else "Turn On"
            
            if st.button(button_text, key=f"{key_prefix}_toggle"):
                success = self.controller.control_light(
                    light, 
                    not current_light_state, 
                    st.session_state.transition_time
                )
                if success:
                    st.rerun()
                else:
                    st.error("Failed to control light")
        
        # Brightness control
        bcol1, bcol2 = st.columns([3, 1])
        
        with bcol1:
            current_brightness = self.controller.get_light_brightness(light)
            new_brightness = st.slider(
                "Brightness", 
                min_value=1, 
                max_value=100, 
                value=current_brightness,
                key=f"{key_prefix}_brightness"
            )
            
            # Update brightness if changed and light is on
            if (new_brightness != current_brightness and 
                self.controller.get_light_state(light) and
                abs(new_brightness - current_brightness) > 2):  # Threshold to prevent excessive calls
                
                success = self.controller.set_light_brightness(
                    light, 
                    new_brightness, 
                    st.session_state.transition_time
                )
                if not success:
                    st.error("Failed to set brightness")
        
        with bcol2:
            st.write(f"**{current_brightness}%**")
        
        # Advanced color controls
        if st.session_state.show_advanced:
            color_info = self.controller.get_light_color_info(light)
            
            if color_info and self.controller.get_light_state(light):
                st.markdown("**🎨 Color Controls**")
                
                ccol1, ccol2 = st.columns(2)
                
                with ccol1:
                    # Color picker
                    color_hex = st.color_picker(
                        "Color", 
                        value="#FFFFFF",
                        key=f"{key_prefix}_color"
                    )
                    
                    if st.button("Apply Color", key=f"{key_prefix}_apply_color"):
                        success = self.controller.set_light_color(
                            light, 
                            color_hex, 
                            st.session_state.transition_time
                        )
                        if success:
                            st.rerun()
                        else:
                            st.error("Failed to set color")
                
                with ccol2:
                    # Color temperature (if supported)
                    if 'ct' in color_info and color_info['ct'] > 0:
                        ct_value = st.slider(
                            "Color Temperature", 
                            min_value=153, 
                            max_value=500, 
                            value=color_info.get('ct', 300),
                            key=f"{key_prefix}_ct",
                            help="153=cold white, 500=warm white"
                        )
                        
                        if st.button("Apply Temperature", key=f"{key_prefix}_apply_ct"):
                            try:
                                light.set_state({'ct': ct_value}, transition=st.session_state.transition_time)
                                st.rerun()
                            except Exception as e:
                                st.error(f"Failed to set color temperature: {e}")

    def render_group_controls(self, group):
        """Render enhanced group controls."""
        col1, col2, col3 = st.columns([2.5, 0.5, 1])
        
        with col1:
            # Enhanced emoji mapping
            room_emojis = {
                'living': '🛋️', 'bedroom': '🛏️', 'kitchen': '🍳',
                'bathroom': '🚿', 'dining': '🍽️', 'office': '💼',
                'garage': '🚗', 'garden': '🌺', 'outdoor': '🌳',
                'hallway': '🚪', 'basement': '🏠', 'attic': '🏠',
                'balcony': '🌿', 'patio': '🌿', 'study': '📚',
                'guest': '🛏️', 'master': '🛏️', 'kids': '🧸',
                'laundry': '👕', 'closet': '👔'
            }
            
            emoji = '🏠'  # default
            name_lower = group.name.lower()
            for key, value in room_emojis.items():
                if key in name_lower:
                    emoji = value
                    break
            
            # Show light count
            light_count = len(getattr(group, 'lights', []))
            st.write(f"{emoji} **{group.name}** ({light_count} lights)")
        
        with col2:
            status_icon = "🟢" if self.controller.get_group_state(group) else "⚫"
            st.write(f"Status: {status_icon}")
        
        with col3:
            current_state = self.controller.get_group_state(group)
            button_text = "Turn Off" if current_state else "Turn On"
            
            if st.button(button_text, key=f"group_{group.id_}"):
                success = self.controller.control_group(
                    group, 
                    not current_state, 
                    st.session_state.transition_time
                )
                if success:
                    st.rerun()
                else:
                    st.error("Failed to control group")
        
        # Group brightness control (if group is on)
        if current_state and st.session_state.show_advanced:
            bcol1, bcol2 = st.columns([3, 1])
            
            with bcol1:
                group_brightness = st.slider(
                    f"Group Brightness", 
                    min_value=1, 
                    max_value=100, 
                    value=50,  # Default value since groups don't return brightness
                    key=f"group_{group.id_}_brightness"
                )
                
                if st.button("Apply Group Brightness", key=f"group_{group.id_}_apply_brightness"):
                    success = self.controller.set_group_brightness(
                        group, 
                        group_brightness, 
                        st.session_state.transition_time
                    )
                    if success:
                        st.rerun()
                    else:
                        st.error("Failed to set group brightness")

    def main(self):
        st.set_page_config(
            page_title="Philips Hue Control Panel",
            page_icon="💡",
            layout="wide",
            initial_sidebar_state="expanded"
        )
        
        st.title("💡 Philips Hue Control Panel")
        
        # Render sidebar settings
        self.render_sidebar_settings()
        
        # Load and validate credentials
        bridge_ip, bridge_username = self.credentials.load()
        
        # Check if credentials are valid
        if not bridge_ip or not bridge_username or not self.credentials.is_valid():
            bridge_ip, bridge_username = self.show_bridge_discovery()
            if not bridge_ip or not bridge_username:
                return
        
        try:
            # Initialize controller if not already initialized
            if not self.controller:
                self.controller = HueController(bridge_ip, bridge_username)
            
            # Auto-refresh check
            if self.should_update():
                logger.info(f"Auto-refresh update at {datetime.now().strftime('%H:%M:%S')}")
                st.rerun()
            
            # Render status bar
            self.render_status_bar()
            
            # Get devices with error handling
            try:
                lights = self.controller.get_lights()
                groups = self.controller.get_groups()
            except Exception as e:
                st.error(f"Error fetching devices: {str(e)}")
                if st.button("Clear Cache and Retry"):
                    self.controller.clear_cache()
                    st.rerun()
                return
            
            # Main content tabs
            tab1, tab2, tab3 = st.tabs(["🏠 Groups/Rooms", "💡 All Lights", "📊 Bridge Info"])
            
            with tab1:
                if not groups:
                    st.info("No groups found on your bridge.")
                else:
                    for group in groups:
                        with st.container():
                            self.render_group_controls(group)
                            
                            # Lights in group
                            with st.expander(f"Lights in {group.name}", expanded=False):
                                if hasattr(group, 'lights') and group.lights:
                                    for light_id in group.lights:
                                        light = next((l for l in lights if str(l.id_) == str(light_id)), None)
                                        if light:
                                            with st.container():
                                                st.markdown("---")
                                                self.render_light_controls(light, group.id_)
                                else:
                                    st.info("No lights in this group")
                            
                            st.divider()
            
            with tab2:
                if not lights:
                    st.info("No lights found on your bridge.")
                else:
                    st.subheader(f"All Lights ({len(lights)} total)")
                    
                    # Global controls
                    if st.session_state.show_advanced:
                        gcol1, gcol2, gcol3, gcol4 = st.columns(4)
                        
                        with gcol1:
                            if st.button("🌞 All On"):
                                for light in lights:
                                    self.controller.control_light(light, True, st.session_state.transition_time)
                                st.rerun()
                        
                        with gcol2:
                            if st.button("🌙 All Off"):
                                for light in lights:
                                    self.controller.control_light(light, False, st.session_state.transition_time)
                                st.rerun()
                        
                        with gcol3:
                            if st.button("🔆 Max Brightness"):
                                for light in lights:
                                    if self.controller.get_light_state(light):
                                        self.controller.set_light_brightness(light, 100, st.session_state.transition_time)
                                st.rerun()
                        
                        with gcol4:
                            if st.button("🔅 Dim All"):
                                for light in lights:
                                    if self.controller.get_light_state(light):
                                        self.controller.set_light_brightness(light, 20, st.session_state.transition_time)
                                st.rerun()
                        
                        st.divider()
                    
                    # Individual light controls
                    for light in lights:
                        with st.container():
                            self.render_light_controls(light)
                            st.markdown("---")
            
            with tab3:
                bridge_info = self.controller.get_bridge_info()
                
                if bridge_info:
                    col1, col2 = st.columns(2)
                    
                    with col1:
                        st.subheader("🌉 Bridge Information")
                        st.write(f"**Name:** {bridge_info.get('name', 'Unknown')}")
                        st.write(f"**IP Address:** {self.controller.bridge_ip}")
                        st.write(f"**API Version:** {bridge_info.get('apiversion', 'Unknown')}")
                        st.write(f"**Software Version:** {bridge_info.get('swversion', 'Unknown')}")
                        st.write(f"**Bridge ID:** {bridge_info.get('bridgeid', 'Unknown')}")
                        st.write(f"**Model ID:** {bridge_info.get('modelid', 'Unknown')}")
                    
                    with col2:
                        st.subheader("📊 Statistics")
                        st.metric("Total Lights", len(lights))
                        st.metric("Total Groups", len(groups))
                        
                        lights_on = sum(1 for light in lights if self.controller.get_light_state(light))
                        st.metric("Lights On", lights_on)
                        
                        groups_on = sum(1 for group in groups if self.controller.get_group_state(group))
                        st.metric("Groups On", groups_on)
                    
                    # Connection test
                    st.subheader("🔧 Diagnostics")
                    if st.button("Test Connection"):
                        try:
                            test_lights = self.controller.hue.get_lights()
                            st.success(f"✅ Connection successful! Found {len(test_lights)} lights.")
                        except Exception as e:
                            st.error(f"❌ Connection failed: {str(e)}")
                else:
                    st.warning("Could not retrieve bridge information.")
                            
        except Exception as e:
            st.error(f"Error connecting to Hue bridge: {str(e)}")
            st.info("Try clearing your credentials and setting up the bridge again.")
            
            if st.button("Clear Credentials and Retry"):
                if self.credentials.filepath.exists():
                    self.credentials.filepath.unlink()
                st.rerun()

if __name__ == "__main__":
    app = HueApp()
    app.main()