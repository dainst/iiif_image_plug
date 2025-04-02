#!/bin/bash
# See https://github.com/IIIF/image-validator
#
# This script assumes that the development server is already running at port 4000.
source .venv/bin/activate

pip install iiif-validator

iiif-validate.py -s localhost:4000 -i official_test_image.png --version=3.0 -v