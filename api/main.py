"""
Financial Analysis API
Micro-service FastAPI qui génère une analyse financière narrative via un LLM.

Usage :
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

POST /analyze
    Body : FinancialPayload (voir schéma ci-dessous)
    Retourne : { "analysis": "...", "model": "gpt-4o", "generated_at": "..." }
"""

import os
import json
from datetime import datetime, timezone
from typing import Optional

from dotenv import load_dotenv
load_dotenv()  # charge api/.env automatiquement

import httpx
from fastapi import FastAPI, HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field

# ── Config ─────────────────────────────────────────────────────────────────

API_KEY      = os.getenv("ANALYSIS_API_KEY", "changeme")  # clé pour protéger l'API
LLM_API_KEY  = os.getenv("GITHUB_KEY") or os.getenv("OPENAI_API_KEY")
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://models.inference.ai.azure.com")
LLM_MODEL    = os.getenv("LLM_MODEL",    "gpt-4o")
LLM_TIMEOUT  = int(os.getenv("LLM_TIMEOUT", "120"))

# ── Schémas Pydantic ────────────────────────────────────────────────────────

class YearData(BaseModel):
    fiscal_year: int
    # Compte de résultat
    revenue:                    Optional[float] = None
    commercial_margin:          Optional[float] = None
    commercial_margin_pct:      Optional[float] = None
    value_added:                Optional[float] = None
    ebitda:                     Optional[float] = None
    ebitda_margin_pct:          Optional[float] = None
    ebit:                       Optional[float] = None
    ebit_margin_pct:            Optional[float] = None
    personnel_expenses:         Optional[float] = None
    depreciation_amortization:  Optional[float] = None
    net_income:                 Optional[float] = None
    net_margin_pct:             Optional[float] = None
    # Bilan
    total_assets:               Optional[float] = None
    total_fixed_assets_net:     Optional[float] = None
    total_inventory:            Optional[float] = None
    trade_receivables:          Optional[float] = None
    cash_and_equivalents:       Optional[float] = None
    total_equity:               Optional[float] = None
    financial_debt:             Optional[float] = None
    working_capital_requirement:Optional[float] = None
    net_financial_debt:         Optional[float] = None
    # Ratios
    economic_return:            Optional[float] = None
    return_on_equity:           Optional[float] = None
    financial_autonomy_ratio:   Optional[float] = None
    general_liquidity_ratio:    Optional[float] = None
    reduced_liquidity_ratio:    Optional[float] = None
    debt_ratio:                 Optional[float] = None
    interest_coverage_ratio:    Optional[float] = None
    days_sales_outstanding:     Optional[float] = None
    days_inventory_outstanding: Optional[float] = None
    days_payable_outstanding:   Optional[float] = None
    cash_conversion_cycle:      Optional[float] = None


class FinancialPayload(BaseModel):
    company_name:         str
    sector:               Optional[str] = None
    country:              Optional[str] = "France"
    accounting_standard:  Optional[str] = "pcg"
    cagr_revenue:         Optional[float] = None
    years:                list[YearData] = Field(..., min_length=1)


class AnalysisResponse(BaseModel):
    analysis:     str
    model:        str
    generated_at: str


# ── App ─────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Financial Analysis API",
    description="Génère une analyse financière narrative de qualité professionnelle via LLM.",
    version="1.0.0",
)

security = HTTPBearer()


def verify_api_key(credentials: HTTPAuthorizationCredentials = Security(security)):
    if credentials.credentials != API_KEY:
        raise HTTPException(status_code=401, detail="Clé API invalide")
    return credentials.credentials


# ── Routes ──────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "model": LLM_MODEL, "llm_base": LLM_BASE_URL}


@app.post("/analyze", response_model=AnalysisResponse)
async def analyze(
    payload: FinancialPayload,
    _: str = Depends(verify_api_key),
):
    if not LLM_API_KEY:
        raise HTTPException(status_code=500, detail="LLM API key non configurée (GITHUB_KEY ou OPENAI_API_KEY)")

    prompt = build_prompt(payload)

    async with httpx.AsyncClient(timeout=LLM_TIMEOUT) as client:
        resp = await client.post(
            f"{LLM_BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {LLM_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model":       LLM_MODEL,
                "messages":    [{"role": "user", "content": prompt}],
                "temperature": 0.3,
                "max_tokens":  2048,
            },
        )

    if resp.status_code != 200:
        err = resp.json().get("error", {}).get("message", resp.text)
        raise HTTPException(status_code=502, detail=f"Erreur LLM ({resp.status_code}) : {err}")

    analysis = resp.json()["choices"][0]["message"]["content"].strip()

    return AnalysisResponse(
        analysis=analysis,
        model=LLM_MODEL,
        generated_at=datetime.now(timezone.utc).isoformat(),
    )


# ── Prompt builder ──────────────────────────────────────────────────────────

def fmt(value, suffix="", decimals=0) -> str:
    if value is None:
        return "—"
    if decimals == 0:
        return f"{int(round(value)):,}".replace(",", "\u202f") + suffix
    return f"{value:.{decimals}f}".replace(".", ",") + suffix


def build_prompt(p: FinancialPayload) -> str:
    years = [y.fiscal_year for y in p.years]
    header = "| Indicateur | " + " | ".join(str(y) for y in years) + " |"
    sep    = "|---|" + "---|" * len(years)

    def row(label: str, field: str, suffix: str = "", decimals: int = 0) -> str:
        vals = " | ".join(fmt(getattr(y, field), suffix, decimals) for y in p.years)
        return f"| {label} | {vals} |"

    sections = [
        f"## Société : {p.company_name}",
        f"Secteur : {p.sector or 'N/R'}  |  Référentiel : {(p.accounting_standard or 'pcg').upper()}  |  Pays : {p.country or 'France'}",
        "",
        "### Compte de résultat (€)",
        header, sep,
        row("Chiffre d'affaires",       "revenue",                   " €"),
        row("Marge commerciale",         "commercial_margin",          " €"),
        row("Marge commerciale %",       "commercial_margin_pct",      " %", 1),
        row("Valeur Ajoutée",            "value_added",                " €"),
        row("EBE / EBITDA",              "ebitda",                     " €"),
        row("Marge EBE %",               "ebitda_margin_pct",          " %", 1),
        row("EBIT",                      "ebit",                       " €"),
        row("Marge EBIT %",              "ebit_margin_pct",            " %", 1),
        row("Charges de personnel",      "personnel_expenses",          " €"),
        row("Dotations amortissements",  "depreciation_amortization",  " €"),
        row("Résultat net",              "net_income",                  " €"),
        row("Marge nette %",             "net_margin_pct",              " %", 1),
        "",
        "### Bilan (€)",
        header, sep,
        row("Total actif",               "total_assets",                " €"),
        row("Immobilisations nettes",    "total_fixed_assets_net",      " €"),
        row("Stocks",                    "total_inventory",             " €"),
        row("Créances clients",          "trade_receivables",           " €"),
        row("Trésorerie",                "cash_and_equivalents",        " €"),
        row("Capitaux propres",          "total_equity",                " €"),
        row("Dettes financières",        "financial_debt",              " €"),
        row("BFR",                       "working_capital_requirement", " €"),
        row("Dettes nettes",             "net_financial_debt",          " €"),
        "",
        "### Ratios clés",
        header, sep,
        row("Re — rentabilité éco. %",  "economic_return",             " %", 1),
        row("Rcp — ROE %",              "return_on_equity",            " %", 1),
        row("Autonomie financière %",   "financial_autonomy_ratio",    " %", 1),
        row("Liquidité générale",       "general_liquidity_ratio",     "×",  2),
        row("Liquidité réduite",        "reduced_liquidity_ratio",     "×",  2),
        row("Dettes nettes / EBITDA",   "debt_ratio",                  "×",  2),
        row("Couverture intérêts",      "interest_coverage_ratio",     "×",  1),
        row("DSO — délai clients (j)",  "days_sales_outstanding",      " j"),
        row("DIO — rotation stocks (j)","days_inventory_outstanding",  " j"),
        row("DPO — délai fourn. (j)",   "days_payable_outstanding",    " j"),
        row("CCC — cycle tréso (j)",    "cash_conversion_cycle",       " j"),
        "",
    ]

    if p.cagr_revenue is not None:
        sections.append(
            f"TCAM du CA ({years[0]}→{years[-1]}) : {p.cagr_revenue * 100:.1f} %/an"
        )
        sections.append("")

    sections += [
        "---",
        "",
        f"""## Mission

Tu es un analyste financier senior dans un cabinet de conseil en fusions-acquisitions.
Rédige en français une **analyse financière professionnelle et structurée** de la société {p.company_name}
à partir des données ci-dessus, telle qu'elle figurerait dans un mémorandum d'information
destiné à une **banque, des investisseurs en capital, des actionnaires ou des acquéreurs potentiels**.

### Structure attendue (utilise ces titres en gras) :

**1. Activité et dynamique commerciale**
Analyse l'évolution du CA, de la marge commerciale et de la croissance. Identifie les tendances.

**2. Rentabilité opérationnelle**
Commente les marges (EBE, EBIT, nette), la création de valeur ajoutée et les charges structurelles.

**3. Structure financière et solvabilité**
Apprécie le niveau des capitaux propres, l'endettement, l'autonomie financière et la couverture des intérêts.

**4. Liquidité et gestion du BFR**
Analyse la trésorerie, les ratios de liquidité, le cycle de trésorerie et les rotations.

**5. Forces, risques et points de vigilance**
Identifie les 2-3 forces distinctives et les 2-3 risques ou signaux faibles à surveiller.

**6. Opinion synthétique**
Donne un avis tranché (favorable / réservé / défavorable) avec une justification concise de 2-3 phrases,
comme le ferait un comité de crédit ou un comité d'investissement.

### Contraintes rédactionnelles :
- Ton factuel, professionnel et nuancé — pas de superlatifs gratuits
- Chiffres précis cités à l'appui de chaque affirmation
- Longueur : 550 à 750 mots
- Langue : français courant professionnel""",
    ]

    return "\n".join(sections)
