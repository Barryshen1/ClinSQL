WITH patient_stays AS (
  SELECT
    p.subject_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
max_hr_per_stay AS (
  SELECT
    ps.subject_id,
    ps.stay_id,
    MAX(c.valuenum) AS max_hr
  FROM
    patient_stays ps
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON
    ps.stay_id = c.stay_id
  WHERE
    c.itemid = 220045
    AND c.valuenum IS NOT NULL
  GROUP BY
    ps.subject_id, ps.stay_id
),
max_hr_per_patient AS (
  SELECT
    subject_id,
    MAX(max_hr) AS patient_max_hr
  FROM
    max_hr_per_stay
  GROUP BY
    subject_id
)
SELECT
  PERCENTILE_CONT(patient_max_hr, 0.25) WITHIN GROUP (ORDER BY patient_max_hr) AS q1,
  PERCENTILE_CONT(patient_max_hr, 0.75) WITHIN GROUP (ORDER BY patient_max_hr) AS q3,
  PERCENTILE_CONT(patient_max_hr, 0.75) WITHIN GROUP (ORDER BY patient_max_hr) - PERCENTILE_CONT(patient_max_hr, 0.25) WITHIN GROUP (ORDER BY patient_max_hr) AS iqr
FROM
  max_hr_per_patient;