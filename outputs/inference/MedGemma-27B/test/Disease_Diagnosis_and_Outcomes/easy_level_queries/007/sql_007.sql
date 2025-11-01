WITH RelevantPatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.icd_code = '530.0' -- Primary UGIB code
    AND d.seq_num = 1 -- Primary diagnosis
),
HospitalStay AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate hospital length of stay in hours
    (TIMESTAMP_DIFF(dischtime, admittime, HOUR)) AS los_hours
  FROM
    RelevantPatients
)
SELECT
  PERCENTILE_CONT(0.25, los_hours) AS IQR_25th_percentile,
  PERCENTILE_CONT(0.75, los_hours) AS IQR_75th_percentile
FROM
  HospitalStay;