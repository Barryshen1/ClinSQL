with COPD exacerbation. For female inpatients 75–85 with COPD exacerbation, stratifying them into quartiles by a "composite risk score", and reporting per quartile:" — as the very first line of the SQL script. BigQuery’s parser interpreted this as a SQL statement and failed when it encountered the identifier "exacerbation" after "COPD", which is not a valid SQL keyword or syntax.

Additionally, the SQL query was cut off mid-condition in the `mortality_and_complications` CTE (specifically, `OR (di2.icd_version = 9 AND di2.icd_code IN ('451.1', '451;`), which would cause a syntax error even if the comment were removed.

We must:
1. Remove the natural language comment line entirely — it has no place in SQL.
2. Complete the `d_icd_diagnoses` complication condition list for major complications (fix the truncated `IN ('451.1', '451;` → should be `'451.1', '451.2'` etc.).
3. Ensure all table references use the correct dataset prefix: `physionet-data.mimiciv_3_1_hosp` (already correct).
4. Complete the Elixhauser conditions list with all 31 conditions (we had 30; missing "Chronic kidney disease" — standard Elixhauser includes it; we’ll use the full standard list).
5. Fix the `elixhauser_conditions` to use `long_title` correctly — some conditions like "Chronic pulmonary disease" are correctly mapped, but we must ensure all 31 are present.
6. Compute 90-day mortality correctly using both `deathtime` and `dod` (already done correctly).
7. Compute major complication flag using a comprehensive list of ICD codes for complications (sepsis, renal failure, cardiac arrest, respiratory failure, pneumonia, DVT/PE, etc.).
8. Compute median LOS only for survivors (i.e., those with `ninety_day_mortality = 0`).
9. Compute overall 90-day mortality for the entire cohort (as requested: “broader 75–85 female 90-day mortality”).
10. Use `NTILE(4)` over `elixhauser_score` to create quartiles.
11. Aggregate per quartile: 90-day mortality rate, major complication rate, median LOS (survivors only), and overall 90-day mortality.

We will also:
- Use `DATE_DIFF(dischtime, admittime, DAY)` for LOS in days.
- Ensure `dod` is compared as a date (it’s stored as DATE in MIMIC-IV).
- Avoid trailing semicolons in CTEs (BigQuery doesn’t require them, and they can cause issues in some contexts).

We complete the DVT/PE ICD codes: ICD-9: 451.1 (PE), 451.2 (DVT), 451.8 (other venous embolism), 451.9 (unspecified); ICD-10: I26.0 (PE), I82.4 (DVT), I82.8 (other venous embolism), I82.9 (unspecified).

We also add "Chronic kidney disease" to Elixhauser (standard condition #31).

Final query structure:
- `female_copd_admissions`: filter female, 75–85, with COPD exacerbation.
- `copd_diagnoses`: identify COPD exacerbation admissions.
- `elixhauser_conditions`: define all 31 Elixhauser conditions.
- `elixhauser_score`: count per admission.
- `mortality_and_complications`: compute 90-day mortality and major complications.
- `quartiles`: assign NTILE(4) to elixhauser_score.
- Final SELECT: aggregate per quartile and overall.

sql
WITH female_copd_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

copd_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE (
    -- ICD-9 COPD exacerbation
    di.icd_version = 9 AND di.icd_code IN ('491.21', '491.22', '491.8', '491.9')
    OR
    -- ICD-10 COPD exacerbation
    di.icd_version = 10 AND di.icd_code IN ('J44.0', 'J44.1', 'J44.9')
  )
),

elixhauser_conditions AS (
  SELECT DISTINCT
    icd_code,
    icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE long_title IN (
    'Congestive heart failure',
    'Cardiac arrhythmias',
    'Valvular disease',
    'Pulmonary circulation disorders',
    'Peripheral vascular disorders',
    'Hypertension, uncomplicated',
    'Hypertension, complicated',
    'Paralysis',
    'Other neurological disorders',
    'Chronic pulmonary disease',
    'Diabetes, uncomplicated',
    'Diabetes, complicated',
    'Hypothyroidism',
    'Renal failure',
    'Liver disease',
    'Peptic ulcer disease excluding bleeding',
    'AIDS/HIV',
    'Lymphoma',
    'Metastatic cancer',
    'Solid tumor without metastasis',
    'Rheumatoid arthritis/collagen vascular diseases',
    'Coagulopathy',
    'Obesity',
    'Weight loss',
    'Fluid and electrolyte disorders',
    'Blood loss anemia',
    'Deficiency anemias',
    'Alcohol abuse',
    'Drug abuse',
    'Psychoses',
    'Depression',
    'Chronic kidney disease'
  )
),

elixhauser_score AS (
  SELECT 
    fca.subject_id,
    fca.hadm_id,
    fca.admittime,
    fca.dischtime,
    fca.deathtime,
    COUNT(ec.icd_code) AS elixhauser_score
  FROM female_copd_admissions fca
  INNER JOIN copd_diagnoses cd ON fca.hadm_id = cd.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON fca.hadm_id = di.hadm_id
  LEFT JOIN elixhauser_conditions ec
    ON di.icd_code = ec.icd_code AND di.icd_version = ec.icd_version
  GROUP BY fca.subject_id, fca.hadm_id, fca.admittime, fca.dischtime, fca.deathtime
),

mortality_and_complications AS (
  SELECT 
    es.*,
    CASE 
      WHEN es.deathtime IS NOT NULL AND es.deathtime <= DATE_ADD(es.admittime, INTERVAL 90 DAY)
        THEN 1
      WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(es.admittime, INTERVAL 90 DAY)
        THEN 1
      ELSE 0
    END AS ninety_day_mortality,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di2
        INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic2
          ON di2.icd_code = dic2.icd_code AND di2.icd_version = dic2.icd_version
        WHERE di2.hadm_id = es.hadm_id
          AND (
            -- Sepsis
            (di2.icd_version = 9 AND di2.icd_code IN ('995.91', '995.92'))
            OR (di2.icd_version = 10 AND di2.icd_code IN ('A41.9', 'A41.51', 'A41.52'))
            -- Acute renal failure
            OR (di2.icd_version = 9 AND di2.icd_code IN ('584.5', '584.6', '584.7', '584.8', '584.9'))
            OR (di2.icd_version = 10 AND di2.ic;