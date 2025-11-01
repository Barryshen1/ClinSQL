WITH primary_sepsis AS (
  SELECT DISTINCT
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) >= 0
    AND REGEXP_CONTAINS(
          LOWER(dicd.long_title),
          r'(\bsepsis\b|\bseptic shock\b|\bsepticemia\b|\bseptic\b)'
        )
)

SELECT
  (SELECT COUNT(1) FROM primary_sepsis) AS n_admissions,
  quantiles[OFFSET(25)] AS p25_days,
  quantiles[OFFSET(50)] AS p50_days,
  quantiles[OFFSET(75)] AS p75_days,
  SAFE_CAST(quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS NUMERIC) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM primary_sepsis
);