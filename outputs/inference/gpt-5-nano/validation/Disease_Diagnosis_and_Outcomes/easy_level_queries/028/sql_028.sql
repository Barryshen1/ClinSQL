WITH cap_admissions AS (
  SELECT
    a.hadm_id,
    (TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) / 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON di.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pneumon%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER () AS p25_los_days
FROM cap_admissions
LIMIT 1;