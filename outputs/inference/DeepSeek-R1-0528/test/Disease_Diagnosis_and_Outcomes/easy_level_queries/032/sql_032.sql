WITH cohort AS (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND a.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%')  -- ICD-9 AKI
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')  -- ICD-10 AKI
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) 
        BETWEEN 81 AND 91  -- Age 81-91 at admission
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM cohort;