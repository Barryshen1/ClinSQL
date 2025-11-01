WITH dvt_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.deathtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      LOWER(dicd.long_title) LIKE '%deep vein thrombosis%'
      OR d.icd_code IN (
        'I82.40', 'I82.41', 'I82.42', 'I82.43', 'I82.44', 'I82.45', 'I82.46', 'I82.47', 'I82.48', 'I82.49',
        'I82.81', 'I82.82',
        'I82.90', 'I82.91', 'I82.92', 'I82.93', 'I82.94', 'I82.95', 'I82.96', 'I82.97', 'I82.98', 'I82.99'
      )
    )
),

elixhauser_conditions AS (
  SELECT DISTINCT icd_code
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
    'Diabetes uncomplicated',
    'Diabetes complicated',
    'Hypothyroidism',
    'Renal failure',
    'Liver disease',
    'Peptic ulcer disease excluding bleeding',
    'AIDS/HIV',
    'Lymphoma',
    'Metastatic cancer',
    'Solid tumor without metastasis',
    'Rheumatoid arthritis',
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

elixhauser_counts AS (
  SELECT dp.subject_id, dp.hadm_id,
         COUNT(DISTINCT d.icd_code) AS elixhauser_count
  FROM dvt_patients dp
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON dp.hadm_id = d.hadm_id
  JOIN elixhauser_conditions ec ON d.icd_code = ec.icd_code
  GROUP BY dp.subject_id, dp.hadm_id
),

complications AS (
  SELECT DISTINCT dp.subject_id, dp.hadm_id,
         CASE WHEN EXISTS (
           SELECT 1
           FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
           JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
           WHERE d.hadm_id = dp.hadm_id
             AND dicd.long_title IN (
               'Sepsis',
               'Acute kidney failure',
               'Acute renal failure',
               'Respiratory failure',
               'Cardiac arrest',
               'Cerebral infarction',
               'Cerebral hemorrhage',
               'Subarachnoid hemorrhage',
               'Subdural hemorrhage',
               'Intracranial hemorrhage',
               'Pulmonary embolism',
               'Hemorrhage',
               'Gastrointestinal hemorrhage'
             )
         ) THEN 1 ELSE 0 END AS has_complication
  FROM dvt_patients dp
),

elixhauser_75th AS (
  SELECT PERCENTILE_CONT(elixhauser_count, 0.75) AS p75
  FROM elixhauser_counts
),

cohort AS (
  SELECT dp.*,
         ec.elixhauser_count,
         c.has_complication,
         dp.hospital_expire_flag AS died
  FROM dvt_patients dp
  JOIN elixhauser_counts ec ON dp.subject_id = ec.subject_id AND dp.hadm_id = ec.hadm_id
  JOIN complications c ON dp.subject_id = c.subject_id AND dp.hadm_id = c.hadm_id
  CROSS JOIN elixhauser_75th
  WHERE ec.elixhauser_count > elixhauser_75th.p75
),

composite_risk AS (
  SELECT *,
         elixhauser_count + has_complication + died AS composite_score
  FROM cohort
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(CAST(died AS FLOAT64)) AS thirty_day_mortality_rate,
  AVG(CAST(has_complication AS FLOAT64)) AS major_complication_rate,
  PERCENTILE_CONT(TIMESTAMP_DIFF(deathtime, admittime, DAY), 0.5) AS median_survival_days_for_decedents,
  PERCENTILE_CONT(composite_score, 0.25) AS composite_score_q1,
  PERCENTILE_CONT(composite_score, 0.5) AS composite_score_q2,
  PERCENTILE_CONT(composite_score, 0.75) AS composite_score_q3,
  PERCENTILE_CONT(composite_score, 1.0) AS composite_score_q4
FROM composite_risk
WHERE died = 1 OR died = 0;  -- Include all for composite score, but median survival only applies to decedents;