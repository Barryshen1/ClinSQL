WITH temps AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    CASE 
      WHEN ce.valueuom = 'F' THEN (ce.valuenum - 32) * 5.0 / 9 
      ELSE ce.valuenum 
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND di.category = 'Temperature'
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom IN ('C', 'F')
    AND CASE 
          WHEN ce.valueuom = 'F' THEN (ce.valuenum - 32) * 5.0 / 9 
          ELSE ce.valuenum 
        END BETWEEN 15 AND 50
),
categorized_temps AS (
  SELECT 
    *,
    CASE 
      WHEN temp_c < 36 THEN '<36'
      WHEN temp_c < 38 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category
  FROM temps
),
mi_diagnoses AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code LIKE '410%') OR
    (icd_version = 10 AND icd_code LIKE 'I21%')
  )
),
patient_hadms_per_cat AS (
  SELECT 
    temp_category,
    subject_id,
    hadm_id
  FROM categorized_temps
  GROUP BY temp_category, subject_id, hadm_id
),
patient_mi_per_cat AS (
  SELECT 
    phc.temp_category,
    phc.subject_id,
    LOGICAL_OR(md.hadm_id IS NOT NULL) AS has_mi
  FROM patient_hadms_per_cat phc
  LEFT JOIN mi_diagnoses md
    ON phc.subject_id = md.subject_id
    AND phc.hadm_id = md.hadm_id
  GROUP BY phc.temp_category, phc.subject_id
),
measurements_with_mi AS (
  SELECT 
    ct.temp_category,
    ct.temp_c,
    ct.subject_id,
    pmi.has_mi
  FROM categorized_temps ct
  INNER JOIN patient_mi_per_cat pmi
    ON ct.temp_category = pmi.temp_category
    AND ct.subject_id = pmi.subject_id
)
SELECT 
  temp_category,
  COUNT(*) AS measurement_count,
  COUNT(DISTINCT subject_id) AS unique_patient_count,
  AVG(temp_c) AS mean_temp,
  APPROX_QUANTILES(temp_c, 2)[SAFE_OFFSET(1)] AS median_temp,
  (APPROX_QUANTILES(temp_c, 4)[SAFE_OFFSET(3)] - APPROX_QUANTILES(temp_c, 4)[SAFE_OFFSET(1)]) AS iqr_temp,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN has_mi THEN subject_id END), 
    COUNT(DISTINCT subject_id)
  ) * 100 AS mi_rate_percent
FROM measurements_with_mi
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    ELSE 3
  END;