with an invalid name: `with pulmonary embolism (PE) and high comorbidity (risk score >75th percentile), ...;`. 

In SQL, CTE names must be valid identifiers — they cannot contain spaces, parentheses, or special characters like “(PE)” or “risk score >75th percentile”. The parser encountered “embolism” after “pulmonary” and expected the keyword `AS`, but instead found an identifier that violated SQL naming rules.

Additionally, the original query fragment was not a complete SQL statement — it was a comment-like clinical description mistakenly written as a CTE name.

To fix this:
1. Rename the CTE to a valid identifier, e.g., `pe_high_comorbidity`.
2. Properly define the CTE using `AS` followed by a valid SELECT query that identifies patients with:
   - Male gender
   - Age 81–91 (using `anchor_age` from `patients`)
   - Pulmonary embolism diagnosis (via `diagnoses_icd` joined with `d_icd_diagnoses` where `long_title` contains “pulmonary embolism”)
   - High comorbidity (defined as Charlson or Elixhauser score >75th percentile — since MIMIC-IV does not have a built-in “risk score” column, we must infer this from known comorbidity indices; the most common is Elixhauser, which is available via `elixhauser_quan` in `mimiciv_3_1_hosp.elixhauser_quan` table — note: this table is part of the HOSP module and contains 31 comorbidity indicators and a total score `elixhauser_score`).
3. Calculate:
   - Mean risk score (i.e., mean `elixhauser_score`) for this cohort
   - 90-day mortality (death within 90 days of admission — use `dod` from `patients` and `admittime` from `admissions`)
   - Compare AKI/ARDS rates and LOS among survivors vs. all inpatients (need to define AKI/ARDS via ICD codes and LOS from `admissions`)
   - Provide matched-profile risk percentile (i.e., the 75th percentile threshold used for inclusion)

We must use:
- `physionet-data.mimiciv_3_1_hosp.admissions`
- `physionet-data.mimiciv_3_1_hosp.patients`
- `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
- `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
- `physionet-data.mimiciv_3_1_hosp.elixhauser_quan` — for comorbidity score
- `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` — to identify AKI/ARDS

Note: MIMIC-IV does not have a direct “risk score” column — we use `elixhauser_score` as the proxy for comorbidity burden. The 75th percentile of `elixhauser_score` in the entire cohort is calculated as a reference.

We will:
1. Define the PE + high comorbidity cohort (males, 81–91, PE diagnosis, elixhauser_score > 75th percentile)
2. Compute mean elixhauser_score and 90-day mortality for this cohort
3. Compute AKI/ARDS rates and LOS for survivors in this cohort
4. Compare to all inpatients (same age/gender) — but note: the question asks for comparison “among survivors to all inpatients” — we interpret this as: compare AKI/ARDS and LOS of survivors in the PE/high-comorbidity group to all other inpatients in the same age/gender group (i.e., matched profile)
5. Report the 75th percentile risk score used as threshold

We assume “90-day mortality” = death within 90 days of admission (using `dod` and `admittime`).

We assume AKI = ICD-9: 584.x or ICD-10: N17.x; ARDS = ICD-9: 518.5 or ICD-10: J80

We use `d_icd_diagnoses` to match `icd_code` and `icd_version` to these conditions.

We use `admissions.los` for length of stay.

We will use a single query with multiple CTEs to compute all required metrics.

sql
WITH pe_high_comorbidity AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    eq.elixhauser_score,
    CASE
      WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS ninety_day_mortality
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.elixhauser_quan eq ON a.subject_id = eq.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(dic.long_title) LIKE '%pulmonary embolism%'
    AND eq.elixhauser_score IS NOT NULL
),

-- Calculate 75th percentile of elixhauser_score among all male 81-91 with PE
percentile_threshold AS (
  SELECT PERCENTILE_CONT(elixhauser_score, 0.75) AS p75_score
  FROM pe_high_comorbidity
),

-- Define AKI and ARDS ICD codes
aki_ards_codes AS (
  SELECT 'ICD9' AS icd_version, '5849' AS icd_code UNION ALL
  SELECT 'ICD9', '5845' UNION ALL
  SELECT 'ICD9', '5846' UNION ALL
  SELECT 'ICD9', '5847' UNION ALL
  SELECT 'ICD9', '5848' UNION ALL
  SELECT 'ICD10', 'N179' UNION ALL
  SELECT 'ICD10', 'N170' UNION ALL
  SELECT 'ICD10', 'N171' UNION ALL
  SELECT 'ICD10', 'N172' UNION ALL
  SELECT 'ICD10', 'N178' UNION ALL
  SELECT 'ICD9', '5185' UNION ALL
  SELECT 'ICD10', 'J80'
),

-- Identify AKI/ARDS in the PE/high-comorbidity cohort
aki_ards_in_pe AS (
  SELECT DISTINCT
    phc.subject_id,
    CASE WHEN di.icd_code IN (SELECT icd_code FROM aki_ards_codes WHERE icd_version = di.icd_version) THEN 1 ELSE 0 END AS has_aki_ards
  FROM pe_high_comorbidity phc
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON phc.hadm_id = di.hadm_id
),

-- Calculate AKI/ARDS rate and LOS for survivors in PE/high-comorbidity cohort
survivors_aki_ards_los AS (
  SELECT
    AVG(phc.elixhauser_score) AS mean_risk_score,
    AVG(phc.ninety_day_mortality) AS ninety_day_mortality_rate,
    AVG(COALESCE(aai.has_aki_ards, 0)) AS aki_ards_rate_survivors,
    AVG(CASE WHEN phc.ninety_day_mortality = 0 THEN a.los END) AS los_survivors
  FROM pe_high_comorbidity phc
  LEFT JOIN aki_ards_in_pe aai ON phc.subject_id = aai.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON phc.hadm_id = a.hadm_id
  WHERE phc.ninety_day_mortality = 0
),

-- Calculate AKI/ARDS rate and LOS for all male 81-91 inpatients (matched profile)
all_matched_inpatients AS (
  SELECT
    AVG(COALESCE(aai.has_aki_ards, 0)) AS aki_ards_rate_all,
    AVG(a.los) AS los_all
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  LEFT JOIN aki_ards;