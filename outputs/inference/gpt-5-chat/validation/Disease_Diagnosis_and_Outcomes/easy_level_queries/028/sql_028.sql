WITH cap_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
      OR (d.icd_version = 10 AND (
          STARTS_WITH(d.icd_code, 'J15')
          OR STARTS_WITH(d.icd_code, 'J16')
          OR STARTS_WITH(d.icd_code, 'J18')
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS los_25th_percentile_days
FROM cap_admissions;