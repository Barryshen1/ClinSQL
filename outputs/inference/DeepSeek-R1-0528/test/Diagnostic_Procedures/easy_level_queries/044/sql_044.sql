WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),
mcs_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%extracorporeal%' OR
    LOWER(long_title) LIKE '%balloon pump%' OR
    LOWER(long_title) LIKE '%assist device%' OR
    LOWER(long_title) LIKE '%ventricular assist%' OR
    LOWER(long_title) LIKE '%vad%' OR
    LOWER(long_title) LIKE '%ecmo%' OR
    LOWER(long_title) LIKE '%intra-aortic%'
),
patient_procedure_counts AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT p.icd_code) AS distinct_mcs_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN mcs_procedures m
    ON p.icd_code = m.icd_code
    AND p.icd_version = m.icd_version
  GROUP BY c.subject_id
)
SELECT STDDEV(distinct_mcs_count) AS sd_distinct_procedures
FROM patient_procedure_counts;