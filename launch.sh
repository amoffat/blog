#!/bin/bash
set -ex
bundle exec jekyll serve --host 0.0.0.0 --watch $@
