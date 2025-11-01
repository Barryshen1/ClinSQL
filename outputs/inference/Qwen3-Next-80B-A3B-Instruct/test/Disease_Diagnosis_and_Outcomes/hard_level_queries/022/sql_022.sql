WITH patients_40_50_female AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

aki_creatinine AS (
  SELECT DISTINCT
    le.subject_id,
    le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'
    AND le.valuenum >= 1.3
),

elixhauser_comorbidities AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code
    AND di.icd_version = did.icd_version
  WHERE did.long_title IN (
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
    'Depression'
  )
),

ards_diagnosis AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code
    AND di.icd_version = did.icd_version
  WHERE did.icd_code IN ('J80', '518.82')
),

composite_risk AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(e.icd_code) AS elixhauser_count,
    CASE WHEN a.hadm_id IS NOT NULL THEN 50 ELSE 0 END AS ards_flag,
    5 * COUNT(e.icd_code) + CASE WHEN a.hadm_id IS NOT NULL THEN 50 ELSE 0 END AS composite_risk
  FROM patients_40_50_female p
  JOIN aki_creatinine aki ON p.subject_id = aki.subject_id AND p.hadm_id = aki.hadm_id
  LEFT JOIN elixhauser_comorbidities e ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
  LEFT JOIN ards_diagnosis a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  GROUP BY p.subject_id, p.hadm_id, a.hadm_id
),

quintiles AS (
  SELECT
    cr.*,
    NTILE(5) OVER (ORDER BY cr.composite_risk) AS risk_quintile
  FROM composite_risk cr
),

survivor_los AS (
  SELECT
    q.risk_quintile,
    i.los
  FROM quintiles q
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON q.subject_id = i.subject_id AND q.hadm_id = i.hadm_id
  WHERE q.dod IS NULL OR DATE_DIFF(q.dod, q.dischtime, DAY) > 30
)

SELECT
  q.risk_quintile,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(CASE WHEN q.dod IS NOT NULL AND DATE_DIFF(q.dod, q.dischtime, DAY) <= 30 THEN 1 ELSE 0 END) / COUNT(*), 2) AS thirty_day_mortality_pct,
  ROUND(100.0 * SUM(CASE WHEN q.ards_flag = 50 THEN 1 ELSE 0 END) / COUNT(*), 2) AS ards_cooccurrence_pct,
  ROUND(PERCENTILE_CONT(s.los, 0.5) OVER (), 2) AS median_survivor_los_days
FROM quintiles q
LEFT JOIN survivor_los s ON q.risk_quintile = s.risk_quintile
GROUP BY q.risk_quintile
ORDER BY q.risk_quintile;