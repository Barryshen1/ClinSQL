WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 60 AND 70
),

hospitalized_admissions AS (
  SELECT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM filtered_patients)
),

atorvastatin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATETIME_DIFF(p.stoptime, p.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN hospitalized_admissions ha
    ON p.hadm_id = ha.hadm_id
  WHERE LOWER(p.drug) LIKE '%atorvastatin%'
    AND REGEXP_CONTAINS(p.dose_val_rx, r'^(40|50|60|70|80)$|^([4-7][0-9]|80)-([4-7][0-9]|80)$')
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
),

quartiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS q
  FROM atorvastatin_prescriptions
)

SELECT
  q[ORDINAL(3)] - q[ORDINAL(1)] AS iqr_days
FROM quartiles;