WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    (p.anchor_year - p.anchor_age) AS birth_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 42 AND 52
),
amiodarone_prescriptions AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ep.subject_id = p.subject_id
    AND ep.hadm_id = p.hadm_id
  WHERE p.drug LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime
)
SELECT
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS p25_duration_hours
FROM amiodarone_prescriptions;