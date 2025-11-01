WITH heart_items AS (
  -- Identify heart-rate-related itemids in ICU d_items
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%heart-rate%'
     OR LOWER(abbreviation) = 'hr'
),
mi_hadm AS (
  -- Flag hospital admissions with an acute MI diagnosis (ICD-9 410* or ICD-10 I21*/I22*)
  SELECT DISTINCT hadm_id,
         1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410'))
     OR (icd_version = 10 AND REGEXP_CONTAINS(UPPER(icd_code), r'^(I21|I22)'))
),
hr_per_stay AS (
  -- Compute mean heart rate per ICU stay for the target cohort (male, age 62-72)
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
  JOIN heart_items hi
    ON ce.itemid = hi.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.valuenum IS NOT NULL
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
)
SELECT
  CASE
    WHEN mean_hr < 60 THEN '<60 bpm'
    WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99 bpm'
    WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119 bpm'
    ELSE '>=120 bpm'
  END AS hr_category,
  COUNT(*) AS icu_stay_count,
  ROUND(100.0 * SUM(COALESCE(m.has_mi, 0)) / COUNT(*), 1) AS percent_with_acute_mi
FROM hr_per_stay h
LEFT JOIN mi_hadm m
  ON h.hadm_id = m.hadm_id
GROUP BY hr_category
ORDER BY
  CASE hr_category
    WHEN '<60 bpm' THEN 1
    WHEN '60-99 bpm' THEN 2
    WHEN '100-119 bpm' THEN 3
    WHEN '>=120 bpm' THEN 4
    ELSE 5
  END;