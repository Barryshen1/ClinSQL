WITH ugib_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.subject_id = di.subject_id
     AND a.hadm_id = di.hadm_id
     AND di.seq_num = 1  -- primary diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%upper%'
    AND (
      LOWER(dd.long_title) LIKE '%bleed%'
      OR LOWER(dd.long_title) LIKE '%hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%bleeding%'
    )
    AND a.dischtime IS NOT NULL
    AND LOWER(p.gender) = 'f'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
)

SELECT
  quantiles[OFFSET(1)] AS q1,  -- 25th percentile
  quantiles[OFFSET(3)] AS q3,  -- 75th percentile
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(LOS_days, 4) AS quantiles
  FROM ugib_admissions
);