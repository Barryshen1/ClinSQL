WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    a.admittime,
    a.dischtime,
    p.dod,
    c.valuenum AS sapsii,
    i.los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.9'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    ) AS has_heart_failure,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%'))
        )
    ) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON i.stay_id = c.stay_id AND c.itemid = 223924
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),
cohort_median AS (
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sapsii) AS median_sapsii
  FROM cohort
  WHERE sapsii IS NOT NULL
),
all_females AS (
  SELECT c.valuenum AS sapsii
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON i.stay_id = c.stay_id AND c.itemid = 223924
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),
percentile_calc AS (
  SELECT 
    COUNTIF(sapsii <= (SELECT median_sapsii FROM cohort_median)) * 100.0 / COUNT(*) AS risk_percentile
  FROM all_females
  WHERE sapsii IS NOT NULL
)
SELECT
  (SELECT median_sapsii FROM cohort_median) AS median_sapsii,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sapsii) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sapsii) AS iqr_sapsii,
  COUNTIF(dod IS NOT NULL AND dod <= dischtime + INTERVAL '30 day') / COUNT(*) AS mortality_30day,
  COUNTIF(has_sepsis) / COUNT(*) AS complication_rate,
  AVG(CASE WHEN (dod IS NULL OR dod > dischtime + INTERVAL '30 day') THEN los END) AS avg_los_survivors,
  (SELECT risk_percentile FROM percentile_calc) AS risk_percentile
FROM cohort
WHERE sapsii IS NOT NULL;