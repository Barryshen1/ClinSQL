WITH cohort AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.icd_version = 10
    AND REGEXP_CONTAINS(dd.icd_code, r'^J1[2-8]')
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime  -- ensure positive LOS
  GROUP BY a.hadm_id, a.admittime, a.dischtime
)
SELECT 
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los
FROM cohort;