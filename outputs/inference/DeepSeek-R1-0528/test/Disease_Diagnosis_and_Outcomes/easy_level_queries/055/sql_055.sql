WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND di.seq_num = 1  -- Primary diagnosis
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('584.5', '584.6', '584.7', '584.8', '584.9'))
      OR
      (di.icd_version = 10 AND di.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'))
    )
    AND a.dischtime > a.admittime  -- Ensure valid LOS
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM cohort;