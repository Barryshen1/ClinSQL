WITH relevant_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
), sepsis_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM
    relevant_admissions AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    d.seq_num = 1 -- Primary diagnosis
    AND icd.long_title LIKE '%sepsis%'
    AND icd.long_title LIKE '%septic shock%'
), los_calculation AS (
  SELECT
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admitime, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admitime, DAY)
    END AS los
  FROM
    sepsis_admissions
)
SELECT
  PERCENTILE_CONT(0.25, los) AS q1,
  PERCENTILE_CONT(0.75, los) AS q3,
  PERCENTILE_CONT(0.75, los) - PERCENTILE_CONT(0.25, los) AS iqr
FROM
  los_calculation;