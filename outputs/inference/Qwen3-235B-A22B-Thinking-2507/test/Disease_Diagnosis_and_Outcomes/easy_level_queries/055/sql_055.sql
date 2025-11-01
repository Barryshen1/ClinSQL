WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 37 AND 47
    AND a.dischtime IS NOT NULL
),
aki_primary AS (
  SELECT
    fa.hadm_id,
    fa.los_days
  FROM
    filtered_admissions fa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los_days
FROM
  aki_primary;