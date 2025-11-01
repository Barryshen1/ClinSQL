WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),
cohort_patients AS (
  SELECT 
    c.subject_id,
    MAX(CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS had_mi
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code LIKE '410%')
      OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  ) mi ON c.hadm_id = mi.hadm_id
  GROUP BY c.subject_id
),
temp_measurements AS (
  SELECT 
    c.subject_id,
    ce.valuenum,
    CASE 
      WHEN ce.valuenum < 36 THEN '<36'
      WHEN ce.valuenum < 38 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.hadm_id = ce.hadm_id AND c.subject_id = ce.subject_id
  WHERE ce.itemid = 223762
    AND ce.valuenum IS NOT NULL
)
SELECT
  temp_category,
  AVG(valuenum) AS mean_temp,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_temp,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr,
  COUNT(DISTINCT tm.subject_id) AS unique_patients,
  COUNT(*) AS measurement_count,
  COUNT(DISTINCT CASE WHEN cp.had_mi = 1 THEN tm.subject_id END) / COUNT(DISTINCT tm.subject_id) AS mi_rate
FROM temp_measurements tm
INNER JOIN cohort_patients cp
  ON tm.subject_id = cp.subject_id
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    WHEN '>=38' THEN 3
  END;