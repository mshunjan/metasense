FROM python:3.9-slim-bullseye as base 
RUN apt-get update && apt-get install -y \
    curl \
    procps

FROM base as compiler 

ENV POETRY_VERSION=1.2.0 \
    POETRY_HOME=/opt/poetry \
    POETRY_VIRTUALENVS_IN_PROJECT=true

ENV PATH="$POETRY_HOME/bin:$PATH"
RUN curl -sSL https://install.python-poetry.org | POETRY_VERSION=${POETRY_VERSION} POETRY_HOME=${POETRY_HOME} python3 -

# Copy Dependency Files
# COPY poetry.lock .
COPY pyproject.toml .

RUN poetry install --no-interaction --no-ansi -vvv

FROM base as runtime 
COPY --from=compiler .venv .venv

ENV PATH="/.venv/bin:$PATH" 
