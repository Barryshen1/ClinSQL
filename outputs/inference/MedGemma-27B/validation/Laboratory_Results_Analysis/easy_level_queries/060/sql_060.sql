WITH relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'J18.9' -- Pneumonia, unspecified
    AND p.gender = 'M'
    -- AND a.anchor_age = 67 -- Removed this line as anchor_age is not in admissions table
), glucose_measurements AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.charttime,
    r.valuenum AS glucose_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS r
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON r.itemid = di.itemid
  WHERE
    di.label LIKE 'Glucose'
    AND r.valuenum IS NOT NULL
    AND r.valueuom = 'mg/dL'
), first_24h_glucose AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.glucose_value
  FROM glucose_measurements AS g
  JOIN relevant_admissions AS ra
    ON g.subject_id = ra.subject_id AND g.hadm_id = ra.hadm_id
  WHERE
    g.charttime BETWEEN ra.admittime AND TIMESTAMP_ADD(ra.admittime, INTERVAL 24 HOUR)
)
SELECT
  PERCENTILE_CONT(0.75, glucose_value)
FROM first_24h_glucose;