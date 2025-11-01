WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code
        AND diag.icd_version = d.icd_version
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND LOWER(d.long_title) LIKE '%pneumonia%'
    )
)
SELECT 
  APPROX_QUANTILES(DATE_DIFF(dischtime, admittime, DAY), 100)[OFFSET(25)] AS los_25th_percentile
FROM cohort
WHERE age_at_admission BETWEEN 49 AND 59;