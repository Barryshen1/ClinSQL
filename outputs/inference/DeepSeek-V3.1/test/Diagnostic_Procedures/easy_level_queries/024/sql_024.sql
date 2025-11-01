WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

proc_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT picd.icd_code) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
    ON c.hadm_id = picd.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON picd.icd_code = dip.icd_code 
      AND picd.icd_version = dip.icd_version
  WHERE (
      dip.long_title LIKE '%coronary angiograph%'
      OR dip.long_title LIKE '%percutaneous coronary intervention%'
      OR dip.long_title LIKE '%PCI%'
      OR dip.long_title LIKE '%coronary artery stent%'
    )
  GROUP BY c.hadm_id
)

SELECT
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75
FROM proc_counts;