WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.subject_id = d_icd.subject_id
    AND a.hadm_id = d_icd.hadm_id
    AND d_icd.seq_num = 1  -- Primary diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code
    AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 52 AND 62
    AND (LOWER(d.long_title) LIKE '%acute kidney failure%' 
         OR LOWER(d.long_title) LIKE '%acute kidney injury%')
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los
FROM eligible_admissions;