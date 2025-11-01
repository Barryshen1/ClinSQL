WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')  -- Fixed pattern (removed dot)
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
)
SELECT 
  quantiles[OFFSET(250)] AS q1,
  quantiles[OFFSET(750)] AS q3,
  quantiles[OFFSET(750)] - quantiles[OFFSET(250)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(los_days, 1000) AS quantiles
  FROM cohort
);