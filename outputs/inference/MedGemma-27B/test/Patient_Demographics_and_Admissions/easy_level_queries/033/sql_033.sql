WITH relevant_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),
dialysis_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON
    p.subject_id = d.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
  ON
    d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (icd.long_title LIKE '%renal failure%'
    OR icd.long_title LIKE '%end-stage renal disease%'
    OR icd.long_title LIKE '%kidney failure%'
    OR icd.long_title LIKE '%dialysis%')
),
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        dialysis_patients
    )
),
los_calculation AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
  FROM
    patient_admissions AS pa
)
SELECT
  STDDEV(los_days)
FROM
  los_calculation;