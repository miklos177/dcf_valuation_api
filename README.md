## License
Distributed under the GNU General Public License v3.0.  
See the file `LICENSE` for details.

# dcf_valuation_api
Objetivo general: construir un pipeline reproducible y testeado que pase de ingresar datos a emitir un valor intrínseco por acción con evidencia de que cada módulo funciona de forma aislada y en conjunto.

# 📈 **my\_dcf\_app**

*Enterprise‑grade FastAPI service to compute the intrinsic value of any listed company using a Free‑Cash‑Flow Discounted Cash‑Flow (DCF) model.*

---

## 1 · Objetivo

- **Automatizar** la valoración fundamental “value + deep‑tech” mediante DCF.
- **Servirla vía API** (REST) para que otros sistemas —u otro micro‑servicio de screening— puedan invocarla.
- **Escalar** sin dolor: cálculo síncrono en desarrollo, asíncrono (Celery) y horizontal en producción.
- **Trazabilidad & auditoría**: cada ejecución guarda sus datos de entrada, supuestos y resultado final.

---

## 2 · Funcionalidades

| Tipo                     | Descripción                                                               | Endpoint / módulo                 | Entrada                                      | Salida                                                   |
| ------------------------ | ------------------------------------------------------------------------- | --------------------------------- | -------------------------------------------- | -------------------------------------------------------- |
| **Run DCF (sync)**       | Ejecuta el pipeline completo y devuelve el resultado en la misma llamada. | `POST /api/v1/dcf/run`            | JSON con CSV embebidos *o* tickers + drivers | JSON con valor intrínseco, rango y tabla de sensibilidad |
| **Run DCF (async)**      | Dispara un job largo en una cola y devuelve `task_id`.                    | `POST /api/v1/dcf/async`          | igual que arriba                             | `task_id`, `status`                                      |
| **Consultar proyección** | Obtiene los años proyectados (ventas, márgenes, FCFF).                    | `GET /api/v1/dcf/{id}/projection` | –                                            | JSON                                                     |
| **Descargar informe**    | PDF/Markdown con supuestos, gráficos, sensibilidad.                       | `GET /api/v1/dcf/{id}/report.pdf` | –                                            | `application/pdf`                                        |
| **Ping**                 | Health‑check                                                              | `GET /api/v1/ping`                | –                                            | `"pong"`                                                 |

---

## 3 · Estructura de carpetas (monolito → micro‑servicio)

```text
my_dcf_app
│
├─ app/                         # código ejecutable
│  ├─ main.py                   # FastAPI + routers
│  ├─ api/                      # capa HTTP
│  │  └─ v1/
│  │     ├─ endpoints/
│  │     │  ├─ dcf.py
│  │     │  ├─ jobs.py
│  │     │  ├─ projections.py
│  │     │  ├─ reports.py
│  │     │  └─ health.py
│  │     └─ dependencies.py
│  ├─ core/                     # infraestructura transversal
│  │  ├─ config.py
│  │  ├─ celery_app.py
│  │  ├─ security.py
│  │  └─ cache.py
│  ├─ models/                   # entidades de dominio
│  │  ├─ financials.py
│  │  ├─ drivers.py
│  │  ├─ wacc.py
│  │  ├─ dcf_result.py
│  │  └─ enums.py
│  ├─ schemas/                  # validación/serialización (Pydantic)
│  │  ├─ inputs.py
│  │  └─ outputs.py
│  ├─ repositories/             # persistencia & fuentes externas
│  │  ├─ database.py
│  │  ├─ files.py
│  │  └─ external_api.py
│  ├─ services/                 # **lógica de negocio**
│  │  ├─ ingest.py
│  │  ├─ forecast.py
│  │  ├─ wacc.py
│  │  ├─ terminal.py
│  │  ├─ discount.py
│  │  ├─ equity.py
│  │  ├─ sensitivities.py
│  │  ├─ report.py
│  │  └─ tasks.py
│  └─ utils/
│     ├─ logging.py
│     ├─ exceptions.py
│     └─ validators.py
│
├─ tests/                       # pytest: unit, integration, api
│
├─ data_sample/                 # CSV de prueba (ASML, Palantir…)
├─ docs/                        # documentación de cada módulo
│
├─ Dockerfile
├─ docker-compose.yml
├─ .env.example
├─ pyproject.toml
└─ README.md                    # ← este archivo
```

> **Regla de oro:** *`api`** expone*, *`services`** piensan*, *`repositories`** guardan/buscan*, *`models`** definen*, *`utils`** ayudan*.

---

## 4 · Mapa de clases clave

| Clase (path) | Resumen                                       | Escalar / extender                                          |
| ------------ | --------------------------------------------- | ----------------------------------------------------------- |
| ``           | Dataclass con campos “revenues”, “ebit”, etc. | Añadir métodos `growth_rate()`, soportar IFRS/US‑GAAP flags |
| ``           | Pydantic; contiene los supuestos del usuario. | Validaciones condicionales (p.ej. *capex\_pct\_sales* ≤ 1)  |
| ``           | Proyecta 3‑10 años de P&L y FCFF.             | Sustituir por modelo ML si se desea                         |
| ``           | Devuelve WACC; maneja beta delever/relever.   | Enriquecer con curva de tipos y estructura plazo            |
| ``** / **``  | Dos métodos de TV.                            | Feature flag para elegir el default                         |
| ``           | Descuenta FCFF. Acepta WACC serie.            | Portar a NumPy vectorizado para acelerar                    |
| ``           | Resta deuda neta, divide por acciones.        | Incorporar planes de recompra futuros                       |
| ``           | Markdown → PDF con WeasyPrint.                | Cambiar plantilla Jinja para branding                       |
| ``           | Celery task principal.                        | Colocar rate‑limit / retry backoff                          |
| ``           | Wrapper Financial Modeling Prep.              | Sustituir por IEX, Bloomberg o stub offline                 |
| ``           | Carga `.env` y secrets.                       | Migrar a HashiCorp Vault                                    |

---

## 5 · Flujo de datos

```text
           ┌── API (FastAPI) ──┐
           │   JSON/YAML/CSV   │
           ▼                   │
      dependencies.py          │
           ▼                   │
┌────────► services.tasks.run_dcf  (Celery async) ◄─┐
│        (or services.* sync)                      │
│        ▼                                         │
│  ingest.py  ─→  forecast.py  ─→  wacc.py         │
│        │                 │                      │
│        └──── discount.py ┴─ terminal.py ──► equity.py
│                            │
└──── sensitivities.py ◄─────┘
           │
           ▼
  report.py  + repositories.database
           │
           ▼
      JSON / PDF
```

---

## 6 · Datos de entrada / salida

### Ejemplo de entrada mínima (sync)

```jsonc
{
  "ticker": "ASML",
  "drivers": {
    "sales_cagr_yrs1_5": 0.18,
    "ebit_margin_path": [0.32, 0.34, 0.35, 0.36, 0.36],
    "capex_pct_sales": 0.12,
    "perpetual_growth_g": 0.025,
    "mos_pct": 0.25
  }
}
```

### Ejemplo de respuesta

```jsonc
{
  "equity_value": 323000000000,
  "shares_diluted": 401000000,
  "intrinsic_value_per_share": 805,
  "range": {
    "low": 650,
    "high": 920
  },
  "margin_of_safety_price": 604,
  "valuation_date": "2025-07-05",
  "sensitivity_matrix": "s3://bucket/id/heatmap.png",
  "report_pdf": "s3://bucket/id/report.pdf"
}
```

---

## 7 · Escalabilidad & despliegue

| Capa                 | Stateless? | Cómo escalar                                                       |
| -------------------- | ---------- | ------------------------------------------------------------------ |
| **API**              | ✔          | Añadir réplicas FastAPI detrás de un LB (p. ej. NGINX‑Ingress).    |
| **Workers**          | ✔          | `docker-compose scale worker=4` o K8s HPA basado en CPU.           |
| **DB**               | ✖          | Postgres en RDS con read‑replicas; partición por empresa si crece. |
| **Cache**            | ✔          | Redis Cluster para low‑latency IO.                                 |
| **Assets (PDF/img)** | ✔          | S3 + CloudFront, versión con checksum.                             |

---

## 8 · Cómo empezar rápido

```bash
# 1) Clona el repo y entra en él
git clone https://github.com/you/my_dcf_app.git
cd my_dcf_app

# 2) Copia variables de entorno y ajústalas
cp .env.example .env

# 3) Ejecuta chequeos de desarrollo
make dev       # lint + tests

# 4) Levanta la pila local
docker compose up --build
# API disponible en http://localhost:8000/docs
```

---

## 9 · Pruebas

```bash
pytest -q tests/unit         # Unit – funciones puras
pytest tests/integration     # Integration – pipeline con sample
pytest tests/api             # API – endpoints con httpx
```

CI automatizado en **GitHub Actions** (`.github/workflows/ci.yml`).

---

## 10 · Extender a micro‑servicios

| Split          | Nuevo servicio        | Comunicación      |
| -------------- | --------------------- | ----------------- |
| **Ingest**     | `market‑data‑svc`     | gRPC / REST       |
| **Heavy calc** | `dcf‑worker`          | Celery broker     |
| **Report**     | `report‑svc`          | S3 events + queue |
| **Auth**       | `auth‑svc` (Keycloak) | JWT               |

Cada micro‑servicio hereda la parte pertinente de `models/` o expone su propio contrato **protobuf**.

---

## 11 · Roadmap

1. 🔐  OAuth2 + scopes “read\:dcf” “write\:dcf”.
2. 🗂️  Multi‑empresa batch (“valuar watchlist completa”).
3. 🌐  WebSocket streaming para progreso de jobs.
4. 🧮  Monte‑Carlo sobre tasas y márgenes.
5. 📊  UI React con shadcn/ui (fuera del alcance de este repo).

---

## 12 · Contribuir

1. Crea rama `feature/<name>`.
2. Añade tests y docs.
3. Ejecuta `make precommit`.
4. Abre PR con descripción y referencia a issue.

**¡Pull‑requests bienvenidos!** 🎉


