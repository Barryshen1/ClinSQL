WITH pneumonia_cohort AS (
  SELECT DISTINCT 
    ad.hadm_id,
    DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND di.seq_num = 1
    AND di.icd_version = 10
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'pneumonia.*communit')
    AND ad.dischtime IS NOT NULL
    AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) > 0
)

SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los_days
FROM 
  pneumonia_cohort;