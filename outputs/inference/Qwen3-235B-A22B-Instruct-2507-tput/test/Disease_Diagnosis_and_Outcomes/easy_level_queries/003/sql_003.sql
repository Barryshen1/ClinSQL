SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'F'
    AND di.seq_num = 1
    AND di.icd_version = 10
    AND di.icd_code LIKE 'I2%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
)
WHERE
  los_days IS NOT NULL;