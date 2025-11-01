WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    adm.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON
    adm.subject_id = d.subject_id
    AND adm.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND (
      LOWER(dd.long_title) LIKE '%ketoacidosis%'
      OR LOWER(dd.long_title) LIKE '%hyperosmolar%'
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  -- APPROX_QUANTILES returns an array of 101 values for 0th through 100th percentiles
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM
  cohort;