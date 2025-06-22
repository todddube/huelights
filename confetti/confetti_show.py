import pygame
import random
import os
import math
from pygame import mixer

# Initialize Pygame
pygame.init()
mixer.init()

# Set up the display
screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
WIDTH, HEIGHT = screen.get_size()
pygame.display.set_caption("Confetti Celebration")

# Colors for confetti
COLORS = [
    (255, 0, 0),    # Red
    (0, 255, 0),    # Green
    (0, 0, 255),    # Blue
    (255, 255, 0),  # Yellow
    (255, 0, 255),  # Magenta
    (0, 255, 255),  # Cyan
    (255, 165, 0),  # Orange
    (128, 0, 128)   # Purple
]

# Sound effects setup
SOUND_DIR = os.path.join(os.path.dirname(__file__), "sounds")
os.makedirs(SOUND_DIR, exist_ok=True)

# Define sounds we want to use
SOUND_FILES = {
    'pop': ['pop1.wav', 'pop2.wav', 'pop3.wav'],
    'swoosh': ['swoosh1.wav', 'swoosh2.wav'],
    'celebration': 'celebration.wav',
    'background': 'party_loop.wav'
}

# Sound class to manage multiple sound effects
class SoundManager:
    def __init__(self):
        self.sounds = {}
        self.background_music = None
        self.last_sound_time = 0
        self.sound_cooldown = 100  # milliseconds between sounds
        self.load_sounds()
        
    def load_sounds(self):
        # Load sound effects
        for category, files in SOUND_FILES.items():
            if isinstance(files, list):
                self.sounds[category] = []
                for file in files:
                    sound_path = os.path.join(SOUND_DIR, file)
                    try:
                        if os.path.exists(sound_path):
                            self.sounds[category].append(mixer.Sound(sound_path))
                    except:
                        print(f"Could not load sound: {sound_path}")
            else:
                sound_path = os.path.join(SOUND_DIR, files)
                try:
                    if os.path.exists(sound_path):
                        self.sounds[category] = mixer.Sound(sound_path)
                except:
                    print(f"Could not load sound: {sound_path}")
        
        # Try to load background music
        bg_music_path = os.path.join(SOUND_DIR, SOUND_FILES['background'])
        if os.path.exists(bg_music_path):
            try:
                self.background_music = bg_music_path
            except:
                print(f"Could not load background music: {bg_music_path}")
    
    def play_random_sound(self, category, volume=0.5):
        """Play a random sound from a category with cooldown"""
        current_time = pygame.time.get_ticks()
        if current_time - self.last_sound_time < self.sound_cooldown:
            return
            
        if category in self.sounds and self.sounds[category]:
            if isinstance(self.sounds[category], list) and self.sounds[category]:
                sound = random.choice(self.sounds[category])
                sound.set_volume(volume)
                sound.play()
                self.last_sound_time = current_time
            elif not isinstance(self.sounds[category], list):
                self.sounds[category].set_volume(volume)
                self.sounds[category].play()
                self.last_sound_time = current_time
                
    def play_background_music(self, volume=0.3, loops=-1):
        """Start background music loop"""
        if self.background_music:
            try:
                mixer.music.load(self.background_music)
                mixer.music.set_volume(volume)
                mixer.music.play(loops)
            except:
                print("Could not play background music")
                
    def stop_background_music(self):
        """Stop background music"""
        mixer.music.stop()

# Confetti particle class
class Confetti:
    def __init__(self, sound_manager):
        self.x = random.randint(0, WIDTH)
        self.y = random.randint(-HEIGHT, 0)
        self.size = random.randint(5, 15)
        self.color = random.choice(COLORS)
        self.speed = random.uniform(2, 6)
        self.angle = random.uniform(0, 360)
        self.spin = random.uniform(-5, 5)
        self.sound_manager = sound_manager
        self.has_played_sound = False

    def update(self):
        old_y = self.y
        self.y += self.speed
        self.angle += self.spin
        
        # Play swoosh sound randomly for falling confetti
        if random.random() < 0.001:  # 0.1% chance each frame per confetti
            self.sound_manager.play_random_sound('swoosh', 0.2)
            
        # Play pop sound when confetti hits the ground
        if old_y < HEIGHT and self.y >= HEIGHT and not self.has_played_sound:
            if random.random() < 0.3:  # 30% chance to play sound when hitting ground
                self.sound_manager.play_random_sound('pop', 0.4)
                self.has_played_sound = True
                
        # Reset confetti if it goes off screen
        if self.y > HEIGHT:
            self.reset()
    
    def reset(self):
        self.y = random.randint(-50, 0)
        self.x = random.randint(0, WIDTH)
        self.has_played_sound = False

    def draw(self, surface):
        points = [
            (self.x, self.y - self.size),
            (self.x + self.size, self.y),
            (self.x, self.y + self.size),
            (self.x - self.size, self.y)
        ]
        rotated_points = []
        for point in points:
            x = point[0] - self.x
            y = point[1] - self.y
            rx = x * math.cos(math.radians(self.angle)) - y * math.sin(math.radians(self.angle))
            ry = x * math.sin(math.radians(self.angle)) + y * math.cos(math.radians(self.angle))
            rotated_points.append((rx + self.x, ry + self.y))
        pygame.draw.polygon(surface, self.color, rotated_points)

# Create sound manager
sound_manager = SoundManager()

# Create confetti particles
confetti_pieces = [Confetti(sound_manager) for _ in range(100)]

# Show message about sound files
print(f"Sound files should be placed in: {SOUND_DIR}")
print("Required sound files:")
for category, files in SOUND_FILES.items():
    if isinstance(files, list):
        for file in files:
            print(f" - {file}")
    else:
        print(f" - {files}")

# Start background music
sound_manager.play_background_music()

# Main game loop
running = True
clock = pygame.time.Clock()

# Play celebration sound at start
sound_manager.play_random_sound('celebration', 0.7)

while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT or (event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE):
            running = False

    # Update confetti
    screen.fill((0, 0, 0))  # Black background
    for confetti in confetti_pieces:
        confetti.update()
        confetti.draw(screen)

    pygame.display.flip()
    clock.tick(60)

# Clean up
sound_manager.stop_background_music()
pygame.quit()