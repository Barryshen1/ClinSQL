WITH cohort AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND di.seq_num = 1
    AND di.icd_version = 9
    AND (
      di.icd_code LIKE '410%' OR
      di.icd_code LIKE '411%' OR
      di.icd_code LIKE '412%' OR
      di.icd_code LIKE '413%' OR
      di.icd_code LIKE '414%'
    )
    AND a.dischtime IS NOT NULL
)
SELECT
  q[OFFSET(24)] AS p25_LOS_days
FROM (
  SELECT APPROX_QUANTILES(LOS_days, 100) AS q
  FROM cohort
) t;