WITH aki_primary_males AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS los_75th_percentile_days
FROM aki_primary_males
LIMIT 1;