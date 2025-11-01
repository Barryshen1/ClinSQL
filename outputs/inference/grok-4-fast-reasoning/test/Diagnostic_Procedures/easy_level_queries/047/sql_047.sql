WITH cohort_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.hadm_id IS NOT NULL
)
SELECT STDDEV(num_procs) AS sd_num_distinct_procedures
FROM (
  SELECT ca.hadm_id,
         COUNT(CASE 
           WHEN LOWER(dip.long_title) LIKE '%heart%ablation%' 
             OR LOWER(dip.long_title) LIKE '%cardioversion%' 
           THEN 1 
         END) AS num_procs
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON ca.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  GROUP BY ca.hadm_id
);