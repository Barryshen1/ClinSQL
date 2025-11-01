WITH sepsis_icd_codes AS (
  SELECT 'A40%' AS code_pattern UNION ALL
  SELECT 'A41%' UNION ALL
  SELECT 'R65.20' UNION ALL
  SELECT 'R65.21'
),
sepsis_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  CROSS JOIN sepsis_icd_codes s
  WHERE d.icd_code LIKE s.code_pattern
),
cohort AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_diagnoses s ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),
meds_24h AS (
  SELECT p.hadm_id, p.drug, p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
drug_classification AS (
  SELECT hadm_id, drug,
    CASE
      WHEN LOWER(drug) IN (
        'amiodarone', 'sotalol', 'dofetilide', 'quinidine', 'procainamide',
        'haloperidol', 'thioridazine', 'ziprasidone', 'iloperidone',
        'ciprofloxacin', 'levofloxacin', 'moxifloxacin',
        'ondansetron', 'methadone', 'pimozide'
      ) THEN 1
      ELSE 0
    END AS is_qt_drug,
    CASE
      WHEN LOWER(drug) IN (
        'warfarin', 'heparin', 'enoxaparin', 'dalteparin',
        'apixaban', 'rivaroxaban', 'dabigatran', 'edoxaban',
        'clopidogrel', 'prasugrel', 'ticagrelor',
        'aspirin', 'abciximab', 'eptifibatide', 'tirofiban'
      ) THEN 1
      ELSE 0
    END AS is_bleeding_drug
  FROM meds_24h
),
patient_level AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT dc.drug) AS complexity_score,
    MAX(dc.is_qt_drug) AS has_qt_drug,
    MAX(dc.is_bleeding_drug) AS has_bleeding_drug,
    c.los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN drug_classification dc ON c.hadm_id = dc.hadm_id
  GROUP BY c.hadm_id, c.los_days, c.hospital_expire_flag
),
complexity_stats AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS pct_rank,
    PERCENTILE_CONT(complexity_score, 0.75) OVER () AS q75_score
  FROM patient_level
),
top_quartile AS (
  SELECT *
  FROM complexity_stats
  WHERE complexity_score >= q75_score
)
SELECT
  -- Distribution of complexity score by group
  has_qt_drug, has_bleeding_drug,
  COUNT(*) AS n,
  AVG(complexity_score) AS avg_complexity,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  APPROX_QUANTILES(complexity_score, 100)[OFFSET(25)] AS q25_complexity,
  APPROX_QUANTILES(complexity_score, 100)[OFFSET(50)] AS median_complexity,
  APPROX_QUANTILES(complexity_score, 100)[OFFSET(75)] AS q75_complexity,
  -- For top quartile: LOS and mortality
  AVG(CASE WHEN complexity_score >= q75_score THEN los_days END) AS avg_los_top_quartile,
  AVG(CASE WHEN complexity_score >= q75_score THEN hospital_expire_flag END) AS mortality_rate_top_quartile
FROM complexity_stats
GROUP BY has_qt_drug, has_bleeding_drug
ORDER BY has_qt_drug DESC, has_bleeding_drug DESC;