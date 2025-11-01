WITH aki_admissions AS (
  -- Get admissions with primary AKI diagnosis for males aged 52-62
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_code LIKE 'N17%'  -- AKI ICD-10 codes
    AND a.dischtime IS NOT NULL
)

-- Calculate the 75th percentile of LOS
SELECT
  PERCENTILE_CONT(length_of_stay_days, 0.75) OVER() AS p75_length_of_stay_days
FROM
  aki_admissions
LIMIT 1;