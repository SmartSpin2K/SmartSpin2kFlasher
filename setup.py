#!/usr/bin/env python
"""smartspin2kflasher setup script."""
import os

from setuptools import setup, find_packages

from smartspin2kflasher import const

PROJECT_NAME = 'smartspin2kflasher'
PROJECT_PACKAGE_NAME = 'smartspin2kflasher'
PROJECT_LICENSE = 'MIT'
PROJECT_AUTHOR = 'SmartSpin2k'
PROJECT_COPYRIGHT = '2020, SmartSpin2k'
PROJECT_URL = 'https://github.com/doudar/SmartSpin2k'
PROJECT_EMAIL = 'contact@esphome.io'

PROJECT_GITHUB_USERNAME = 'SmartSpin2K'
PROJECT_GITHUB_REPOSITORY = 'SmartSpin2KFlasher'

PYPI_URL = 'https://pypi.python.org/pypi/{}'.format(PROJECT_PACKAGE_NAME)
GITHUB_PATH = '{}/{}'.format(PROJECT_GITHUB_USERNAME, PROJECT_GITHUB_REPOSITORY)
GITHUB_URL = 'https://github.com/{}'.format(GITHUB_PATH)

DOWNLOAD_URL = '{}/archive/{}.zip'.format(GITHUB_URL, const.__version__)

here = os.path.abspath(os.path.dirname(__file__))

with open(os.path.join(here, 'requirements.txt')) as requirements_txt:
    REQUIRES = requirements_txt.read().splitlines()

with open(os.path.join(here, 'README.md')) as readme:
    LONG_DESCRIPTION = readme.read()


setup(
    name=PROJECT_PACKAGE_NAME,
    version=const.__version__,
    license=PROJECT_LICENSE,
    url=GITHUB_URL,
    download_url=DOWNLOAD_URL,
    author=PROJECT_AUTHOR,
    author_email=PROJECT_EMAIL,
    description="ESP8266/ESP32 firmware flasher for SmartSpin2k",
    include_package_data=True,
    zip_safe=False,
    platforms='any',
    test_suite='tests',
    python_requires='>=3.5,<4.0',
    install_requires=REQUIRES,
    long_description=LONG_DESCRIPTION,
    long_description_content_type='text/markdown',
    keywords=['home', 'automation'],
    entry_points={
        'console_scripts': [
            'SmartSpin2KFlasher = smartspin2kflasher.__main__:main'
        ]
    },
    packages=find_packages(include="esphomerelease.*")
)
