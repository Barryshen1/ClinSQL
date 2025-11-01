WITH mcs_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ventricular assist%'
     OR LOWER(long_title) LIKE '%heart assist%'
     OR LOWER(long_title) LIKE '%ecmo%'
     OR LOWER(long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(long_title) LIKE '%impella%'
     OR LOWER(long_title) LIKE '%circulatory assist%'
)
SELECT MAX(num_mcs) AS max_distinct_mcs
FROM (
  SELECT pi.hadm_id, COUNT(DISTINCT pi.icd_code) AS num_mcs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN mcs_codes mc 
    ON pi.icd_code = mc.icd_code 
    AND pi.icd_version = mc.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON pi.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
  GROUP BY pi.hadm_id
) sub;