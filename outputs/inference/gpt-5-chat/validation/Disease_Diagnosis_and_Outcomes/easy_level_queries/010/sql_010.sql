WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.seq_num = 1
    AND (
         (d.icd_version = 9 AND d.icd_code IN ('49121','49122'))
      OR (d.icd_version = 10 AND d.icd_code = 'J441')
    )
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile_days
FROM cohort
LIMIT 1;