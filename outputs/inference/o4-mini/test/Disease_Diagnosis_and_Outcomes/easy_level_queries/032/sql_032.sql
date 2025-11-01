WITH aki_primary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code    = di.icd_code
     AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND LOWER(di.long_title) LIKE '%acute kidney injury%'
),

los_quantiles AS (
  SELECT
    APPROX_QUANTILES(los_days, 100) AS pct_array
  FROM (
    SELECT DISTINCT hadm_id, los_days
    FROM aki_primary
  )
)

SELECT
  pct_array[OFFSET(25)] AS los_q1_days,
  pct_array[OFFSET(75)] AS los_q3_days
FROM
  los_quantiles;