WITH echo_procedures AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    COUNT(DISTINCT p.icd_code) AS num_echo
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE 
    LOWER(d.long_title) LIKE '%echocardiogram%' 
    OR LOWER(d.long_title) LIKE '%echo%'
    AND pt.gender = 'M'
    AND pt.anchor_age BETWEEN 84 AND 94
  GROUP BY p.subject_id, p.hadm_id
)
SELECT MAX(num_echo) AS max_echo_procedures
FROM echo_procedures;