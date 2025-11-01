WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    -- Approximate birth date: using anchor_year and anchor_age
    DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS approx_birth_date,
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) BETWEEN 38 AND 48
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
aki_admissions AS (
  SELECT 
    ba.*,
    CASE WHEN d.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM base_admissions ba
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.icd_code IN (
      'N17.0', 'N17.1', 'N17.8', 'N17.9', 
      'R91.0'   -- Acute kidney failure
    )
  ) d ON ba.hadm_id = d.hadm_id
  WHERE d.hadm_id IS NOT NULL   -- only keep if AKI
),
icu_use AS (
  SELECT 
    aki.hadm_id,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_use
  FROM aki_admissions aki
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON aki.hadm_id = i.hadm_id
),
-- Now, count diagnostics per admission from various tables
lab_counts AS (
  SELECT hadm_id, COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
micro_counts AS (
  SELECT hadm_id, COUNT(*) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
  GROUP BY hadm_id
),
chart_counts AS (
  SELECT hadm_id, COUNT(*) AS chart_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  GROUP BY hadm_id
),
output_counts AS (
  SELECT hadm_id, COUNT(*) AS output_count
  FROM `physionet-data.mimiciv_3_1_icu.outputevents`
  GROUP BY hadm_id
),
omr_counts AS (
  SELECT hadm_id, COUNT(*) AS omr_count
  FROM `physionet-data.mimiciv_3_1_hosp.omr`
  GROUP BY hadm_id
),
total_diagnostics AS (
  SELECT 
    iu.hadm_id,
    iu.icu_use,
    aki.los_days,
    COALESCE(lc.lab_count,0) + COALESCE(mc.micro_count,0) + COALESCE(cc.chart_count,0) + COALESCE(oc.output_count,0) + COALESCE(omc.omr_count,0) AS total_diagnostics
  FROM icu_use iu
  INNER JOIN aki_admissions aki ON iu.hadm_id = aki.hadm_id
  LEFT JOIN lab_counts lc ON iu.hadm_id = lc.hadm_id
  LEFT JOIN micro_counts mc ON iu.hadm_id = mc.hadm_id
  LEFT JOIN chart_counts cc ON iu.hadm_id = cc.hadm_id
  LEFT JOIN output_counts oc ON iu.hadm_id = oc.hadm_id
  LEFT JOIN omr_counts omc ON iu.hadm_id = omc.hadm_id
),
grouped_data AS (
  SELECT 
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    icu_use,
    total_diagnostics
  FROM total_diagnostics
  WHERE los_days BETWEEN 1 AND 7   -- already filtered, but for safety
)
SELECT 
  los_group,
  icu_use,
  COUNT(*) AS num_admissions,
  AVG(total_diagnostics) AS mean_diagnostics,
  MIN(total_diagnostics) AS min_diagnostics,
  MAX(total_diagnostics) AS max_diagnostics
FROM grouped_data
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;