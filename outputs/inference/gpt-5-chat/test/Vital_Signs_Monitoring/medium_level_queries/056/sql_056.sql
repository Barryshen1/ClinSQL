WITH female_elderly_icu AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),
temp_events AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    di.label AS item_label
  FROM female_elderly_icu fe
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fe.subject_id = ce.subject_id
    AND fe.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.unitname = '°C'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 25 AND 45
),
temp_categorized AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum,
    CASE
      WHEN valuenum < 36 THEN '<36'
      WHEN valuenum < 38 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category
  FROM temp_events
),
mi_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (dd.icd_version = 9 AND dd.icd_code LIKE '410%')
     OR (dd.icd_version = 10 AND (dd.icd_code LIKE 'I21%' OR dd.icd_code LIKE 'I22%'))
)
SELECT
  tc.temp_category,
  AVG(tc.valuenum) AS mean_temp,
  PERCENTILE_CONT(tc.valuenum, 0.5) AS median_temp,
  (PERCENTILE_CONT(tc.valuenum, 0.75) - PERCENTILE_CONT(tc.valuenum, 0.25)) AS iqr_temp,
  COUNT(DISTINCT tc.subject_id) AS unique_patient_count,
  COUNT(*) AS measurement_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN mp.subject_id IS NOT NULL THEN tc.subject_id END),
    COUNT(DISTINCT tc.subject_id)
  ) AS mi_rate
FROM temp_categorized tc
LEFT JOIN mi_patients mp
  ON tc.subject_id = mp.subject_id
  AND tc.hadm_id = mp.hadm_id
GROUP BY tc.temp_category
ORDER BY tc.temp_category;