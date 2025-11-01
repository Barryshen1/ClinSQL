SELECT
  PERCENTILE_CONT(los_days, 0.75) AS hospital_los_75th_percentile
FROM (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    a.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND diag.seq_num = 1
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'N17%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND p.anchor_year IS NOT NULL
    AND a.admittime >= DATETIME(p.anchor_year, 1, 1, 0, 0, 0)
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 37 AND 47
);