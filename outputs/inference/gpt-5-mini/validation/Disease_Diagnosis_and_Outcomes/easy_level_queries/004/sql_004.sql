WITH primary_dx AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
    AND (
      LOWER(di.long_title) LIKE '%ketoacidosis%'
      OR LOWER(di.long_title) LIKE '%hyperosmolar%'
      OR LOWER(di.long_title) LIKE '%hyperosmol%'
      OR LOWER(di.long_title) LIKE '%hyperglyc%'     -- covers hyperglycemic / hyperglycaemic variants
      OR LOWER(di.long_title) LIKE '%hyperglyca%'
    )
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  COUNT(*) AS n_admissions
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    primary_dx pd
  ON
    a.hadm_id = pd.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
);