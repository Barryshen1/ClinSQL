WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd1 
        ON d1.icd_code = dd1.icd_code AND d1.icd_version = dd1.icd_version
      WHERE d1.hadm_id = a.hadm_id
        AND (dd1.long_title LIKE '%ischemic heart%' 
             OR dd1.long_title LIKE '%acute coronary syndrome%'
             OR dd1.long_title LIKE '%myocardial infarction%'
             OR dd1.long_title LIKE '%angina pectoris%'
            )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2 
        ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (dd2.long_title LIKE '%chronic obstructive pulmonary disease%' 
             OR dd2.long_title LIKE '%copd%'
             OR dd2.long_title LIKE '%chronic bronchitis%'
             OR dd2.long_title LIKE '%emphysema%'
            )
    )
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM cohort;