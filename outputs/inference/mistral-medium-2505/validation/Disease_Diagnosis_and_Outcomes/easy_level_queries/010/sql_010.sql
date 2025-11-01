WITH copd_admissions AS (
  -- Get admissions for females aged 49-59 with primary COPD exacerbation
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.seq_num = 1  -- Primary diagnosis
    AND di.icd_code IN ('J441', 'J44.1')  -- COPD exacerbation (ICD-10)
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

-- Calculate the 25th percentile of hospital LOS
SELECT
  PERCENTILE_CONT(los_hours, 0.25) OVER() AS percentile_25_los_hours
FROM
  copd_admissions
LIMIT 1;