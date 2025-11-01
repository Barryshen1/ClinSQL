WITH patient_icu AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) AS icu_stay_seq,
    DATE_DIFF(i.outtime, i.intime, DAY) AS icu_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 77 AND 87
    AND i.outtime IS NOT NULL
),
dialysis_patients AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('Z99.2', 'Z49.0')  -- Dialysis ICD-10 codes; adjust as needed
),
first_icu_los AS (
  SELECT
    pi.icu_los_days
  FROM
    patient_icu pi
  INNER JOIN
    dialysis_patients dp
    ON pi.subject_id = dp.subject_id
    AND pi.hadm_id = dp.hadm_id
  WHERE
    pi.icu_stay_seq = 1
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY icu_los_days) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY icu_los_days) AS q3
  FROM
    first_icu_los
)
SELECT
  q1,
  q3,
  q3 - q1 AS iqr
FROM
  percentiles;