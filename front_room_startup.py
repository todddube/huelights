#!/usr/bin/env python3
"""
Front Room Startup Script for Hue Lights
Automatically lights up all front room lights with random colors on startup.
"""

import asyncio
import logging
import sys
import time
import random
from pathlib import Path

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from hue_app import HueCredentials, HueController

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(Path(__file__).parent / 'logs' / 'startup.log')
    ]
)

logger = logging.getLogger(__name__)

class FrontRoomStartup:
    """Startup controller for front room lighting effects."""
    
    def __init__(self):
        self.credentials = HueCredentials()
        self.controller = None
        
    def initialize_controller(self) -> bool:
        """Initialize the Hue controller."""
        try:
            bridge_ip, bridge_username = self.credentials.load()
            if not bridge_ip or not bridge_username:
                logger.error("No valid credentials found. Please set up bridge first using main app.")
                return False
            
            if not self.credentials.is_valid():
                logger.error("Credentials are invalid. Please reconfigure bridge.")
                return False
            
            self.controller = HueController(bridge_ip, bridge_username)
            logger.info("Hue controller initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize controller: {str(e)}")
            return False
    
    def find_front_room(self) -> str:
        """Find the front room in available groups."""
        if not self.controller:
            return None
            
        try:
            groups = self.controller.get_groups()
            
            # Common front room names to check
            front_room_keywords = [
                'front', 'living', 'lounge', 'main', 'sitting',
                'family', 'reception', 'parlor', 'salon'
            ]
            
            for group in groups:
                group_name = getattr(group.metadata, 'name', '').lower()
                
                for keyword in front_room_keywords:
                    if keyword in group_name:
                        logger.info(f"Found front room: {group_name}")
                        return getattr(group.metadata, 'name', '')
            
            # If no specific match, try to use the first room/zone
            if groups:
                first_group = groups[0]
                group_name = getattr(first_group.metadata, 'name', 'Unknown')
                logger.info(f"No specific front room found, using: {group_name}")
                return group_name
            
            logger.warning("No rooms/groups found")
            return None
            
        except Exception as e:
            logger.error(f"Error finding front room: {str(e)}")
            return None
    
    def startup_light_show(self, room_name: str = None, duration: int = 30) -> bool:
        """Execute startup light show in front room."""
        if not self.controller:
            logger.error("Controller not initialized")
            return False
        
        try:
            # Find room if not specified
            if not room_name:
                room_name = self.find_front_room()
                if not room_name:
                    logger.error("Could not find front room")
                    return False
            
            logger.info(f"Starting light show in {room_name} for {duration} seconds")
            
            # Phase 1: Turn on all lights with rainbow colors
            logger.info("Phase 1: Rainbow startup")
            success = self.controller.random_room_lighting(
                room_name, 
                effect_type="rainbow", 
                transition=5, 
                brightness=90
            )
            
            if not success:
                logger.error("Failed to apply rainbow lighting")
                return False
            
            # Wait for initial effect
            time.sleep(8)
            
            # Phase 2: Cycle through different color patterns
            patterns = ["warm", "cool", "random"]
            cycles = duration // (len(patterns) * 6)  # 6 seconds per pattern
            
            for cycle in range(max(1, cycles)):
                for pattern in patterns:
                    logger.info(f"Applying {pattern} pattern (cycle {cycle + 1})")
                    
                    success = self.controller.random_room_lighting(
                        room_name,
                        effect_type=pattern,
                        transition=3,
                        brightness=80
                    )
                    
                    if success:
                        time.sleep(6)
                    else:
                        logger.warning(f"Failed to apply {pattern} pattern")
            
            # Phase 3: Final warm white settling
            logger.info("Phase 3: Settling to warm white")
            room_lights = self.controller.get_lights_in_room(room_name)
            
            for light in room_lights:
                # Set to warm white
                try:
                    self.controller.control_light(light, True, 10)
                    self.controller.set_light_brightness(light, 60, 10)
                    # Warm white XY coordinates
                    self.controller.set_light_color(light, (0.4573, 0.4100), 10)
                except Exception as e:
                    logger.warning(f"Failed to set final state for light: {e}")
            
            logger.info("Startup light show completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error during startup light show: {str(e)}")
            return False
    
    def quick_random_lights(self, room_name: str = None) -> bool:
        """Quick random lighting for front room."""
        if not self.controller:
            logger.error("Controller not initialized")
            return False
        
        try:
            if not room_name:
                room_name = self.find_front_room()
                if not room_name:
                    logger.error("Could not find front room")
                    return False
            
            logger.info(f"Applying quick random lighting to {room_name}")
            
            success = self.controller.random_room_lighting(
                room_name,
                effect_type="random",
                transition=8,
                brightness=85
            )
            
            if success:
                logger.info("Quick random lighting applied successfully")
            else:
                logger.error("Failed to apply quick random lighting")
            
            return success
            
        except Exception as e:
            logger.error(f"Error during quick random lighting: {str(e)}")
            return False

def main():
    """Main entry point for the startup script."""
    # Handle Unicode encoding for Windows console
    import sys
    if sys.platform == "win32":
        import os
        os.system('chcp 65001 >nul 2>&1')  # Set console to UTF-8
    
    try:
        print("🌈 Hue Front Room Startup Script")
    except UnicodeEncodeError:
        print("*** Hue Front Room Startup Script ***")
    
    print("=" * 40)
    
    # Parse command line arguments first
    import argparse
    parser = argparse.ArgumentParser(description="Front Room Hue Startup Script")
    parser.add_argument("--room", type=str, help="Specific room name to target")
    parser.add_argument("--duration", type=int, default=30, help="Light show duration in seconds")
    parser.add_argument("--quick", action="store_true", help="Quick random lighting instead of full show")
    parser.add_argument("--list-rooms", action="store_true", help="List available rooms and exit")
    
    args = parser.parse_args()
    
    startup = FrontRoomStartup()
    
    # Initialize controller
    if not startup.initialize_controller():
        try:
            print("❌ Failed to initialize Hue controller")
        except UnicodeEncodeError:
            print("*** Failed to initialize Hue controller")
        sys.exit(1)
    
    try:
        # List rooms option
        if args.list_rooms:
            try:
                print("\n📍 Available Rooms/Zones:")
            except UnicodeEncodeError:
                print("\n*** Available Rooms/Zones:")
            
            groups = startup.controller.get_groups()
            for i, group in enumerate(groups, 1):
                group_name = getattr(group.metadata, 'name', 'Unknown')
                lights_count = len(getattr(group, 'children', []))
                print(f"  {i}. {group_name} ({lights_count} lights)")
            sys.exit(0)
        
        # Execute lighting effect
        if args.quick:
            try:
                print("🎨 Applying quick random lighting...")
            except UnicodeEncodeError:
                print("*** Applying quick random lighting...")
            success = startup.quick_random_lights(args.room)
        else:
            try:
                print(f"🎪 Starting {args.duration}s light show...")
            except UnicodeEncodeError:
                print(f"*** Starting {args.duration}s light show...")
            success = startup.startup_light_show(args.room, args.duration)
        
        if success:
            try:
                print("✅ Startup lighting completed successfully!")
            except UnicodeEncodeError:
                print("*** Startup lighting completed successfully!")
        else:
            try:
                print("❌ Startup lighting failed")
            except UnicodeEncodeError:
                print("*** Startup lighting failed")
            sys.exit(1)
            
    except KeyboardInterrupt:
        try:
            print("\n🛑 Interrupted by user")
        except UnicodeEncodeError:
            print("\n*** Interrupted by user")
        
        # Try to restore normal lighting
        try:
            room_name = args.room or startup.find_front_room()
            if room_name:
                room_lights = startup.controller.get_lights_in_room(room_name)
                for light in room_lights:
                    startup.controller.set_light_color(light, (0.4573, 0.4100), 5)  # Warm white
        except:
            pass
        sys.exit(0)
    
    except Exception as e:
        try:
            print(f"❌ Unexpected error: {str(e)}")
        except UnicodeEncodeError:
            print(f"*** Unexpected error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()