.DEFAULT_GOAL := help
NODE_BIN=$(CURDIR)/node_modules/.bin

.PHONY: accept clean clean_static check_keywords detect_changed_source_translations extract_translations \
	help html_coverage migrate open-devstack production-requirements pull_translations quality requirements.js \
	requirements start-devstack static stop-devstack test docs static.dev static.watch

include .travis/docker.mk

# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## Display this help message
	@echo "Please use \`make <target>\` where <target> is one of"
	@perl -nle'print $& if m{^[\.a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

static: ## Gather all static assets for production
	$(NODE_BIN)/webpack --config webpack.config.js --display-error-details --progress --optimize-minimize
	python manage.py collectstatic -v 0 --noinput

static.dev:
	$(NODE_BIN)/webpack --config webpack.config.js --display-error-details --progress

static.watch:
	$(NODE_BIN)/webpack --config webpack.config.js --display-error-details --progress --watch

clean_static: ## Remove all generated static files
	rm -rf course_discovery/assets/ course_discovery/static/bundles/

clean: ## Delete generated byte code and coverage reports
	find . -name '*.pyc' -delete
	coverage erase

requirements.js: ## Install JS requirements for local development
	npm install --unsafe-perm ## This flag exists to force node-sass to build correctly on docker. Remove as soon as possible.
	$(NODE_BIN)/bower install --allow-root

requirements: requirements.js ## Install Python and JS requirements for local development
	pip install -r requirements/local.txt -r requirements/django.txt

production-requirements: ## Install Python and JS requirements for production
	pip install -r requirements.txt
	npm install --production
	$(NODE_BIN)/bower install --allow-root --production

upgrade:
	pip install -q -r requirements/pip_tools.txt
	pip-compile --upgrade -o requirements/pip_tools.txt requirements/pip_tools.in
	pip-compile --upgrade -o requirements/docs.txt requirements/docs.in
	pip-compile --upgrade -o requirements/local.txt requirements/local.in
	pip-compile --upgrade -o requirements/production.txt requirements/production.in
	# Let tox control the Django version for tests
	grep -e "^django==" requirements/local.txt > requirements/django.txt
	sed -i.tmp '/^[dD]jango==/d' requirements/local.txt
	rm -rf requirements/local.txt.tmp
	chmod a+rw requirements/*.txt

test: clean ## Run tests and generate coverage report
	## The node_modules .bin directory is added to ensure we have access to Geckodriver.
	PATH="$(NODE_BIN):$(PATH)" pytest --ds=course_discovery.settings.test --durations=25
	coverage combine || true  # will fail if nothing to do, but don't abort if that happens
	coverage report

quality: ## Run pycodestyle and pylint
	isort --check-only --diff --recursive acceptance_tests/ course_discovery/
	pycodestyle --config=.pycodestyle acceptance_tests course_discovery *.py
	PYTHONPATH=./course_discovery/apps pylint --rcfile=pylintrc acceptance_tests course_discovery *.py

validate: quality test ## Run tests and quality checks

migrate: ## Apply database migrations
	python manage.py migrate --noinput
	python manage.py install_es_indexes

html_coverage: ## Generate and view HTML coverage report
	coverage html && open htmlcov/index.html

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
extract_translations: ## Extract strings to be translated, outputting .po and .mo files
	# NOTE: We need PYTHONPATH defined to avoid ImportError(s) on Travis CI.
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py makemessages -l en -v1 --ignore="assets/*" --ignore="static/bower_components/*" --ignore="static/build/*" -d django
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py makemessages -l en -v1 --ignore="assets/*" --ignore="static/bower_components/*" --ignore="static/build/*" -d djangojs
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" i18n_tool dummy
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py compilemessages

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
pull_translations: ## Pull translations from Transifex
	tx pull -af --mode reviewed --minimum-perc=1

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
push_translations: ## Push source translation files (.po) to Transifex
	tx push -s

start-devstack: ## Run a local development copy of the server
	docker-compose up

stop-devstack: ## Shutdown the local development server
	docker-compose down

open-devstack: ## Open a shell on the server started by start-devstack
	docker-compose up -d
	docker exec -it course-discovery env TERM=$(TERM) /edx/app/discovery/devstack.sh open

accept: ## Run acceptance tests
	nosetests --with-ignore-docstrings -v acceptance_tests

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
detect_changed_source_translations: ## Check if translation files are up-to-date
	cd course_discovery && i18n_tool changed

docs:
	cd docs && make html

check_keywords: ## Scan the Django models in all installed apps in this project for restricted field names
	python manage.py check_reserved_keywords --override_file db_keyword_overrides.yml --report_file stich_keyword_report.csv --system STITCH
