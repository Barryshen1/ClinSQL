WITH cabg_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.hadm_id) AS count_cabg
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_icd
    ON proc.icd_code = d_icd.icd_code 
    AND proc.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (LOWER(d_icd.long_title) LIKE '%cabg%' 
         OR LOWER(d_icd.long_title) LIKE '%coronary artery bypass%'
         OR LOWER(d_icd.long_title) LIKE '%bypass graft%')
    AND proc.hadm_id IS NOT NULL
  GROUP BY 
    p.subject_id
  HAVING 
    count_cabg > 0
)
SELECT 
  STDDEV(count_cabg) AS stddev_cabg_per_patient
FROM 
  cabg_counts;