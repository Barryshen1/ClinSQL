WITH cohort AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 10 AND d.icd_code IN ('I60','I61','I62'))
      OR
      (d.icd_version = 9 AND d.icd_code IN ('431','432','433'))
    )
)
SELECT
  STDDEV(los_days) AS sd_los
FROM cohort;