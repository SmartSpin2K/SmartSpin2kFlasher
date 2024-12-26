#!/usr/bin/env python3
import subprocess
import sys
import os

def install_requirements():
    try:
        # Get the directory of this script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        
        # Install all requirements first
        print("Installing requirements...")
        subprocess.check_call([
            sys.executable, 
            "-m", 
            "pip", 
            "install",
            "requests",
            "esptool>=3.2",
            "ifaddr==0.2.0",
            "Pillow>=10.0.0"
        ])
        print("Requirements installed successfully")
        
    except subprocess.CalledProcessError as e:
        print(f"Installation failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)

def main():
    # First install all requirements
    install_requirements()
    
    # Get the directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Add the current directory to Python path
    sys.path.insert(0, script_dir)
    
    # Run the application directly from the current directory
    try:
        from smartspin2kflasher.__main__ import main as app_main
        app_main()
    except Exception as e:
        print(f"Error running SmartSpin2KFlasher: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()