WITH cabg_procs AS (
  SELECT DISTINCT pr.subject_id, pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%bypass%'
    AND LOWER(d.long_title) LIKE '%coronary%'
),
patient_cabg AS (
  SELECT 
    p.subject_id, 
    COUNT(DISTINCT cp.icd_code) AS num_distinct_cabg
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN cabg_procs cp
    ON p.subject_id = cp.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY p.subject_id
)
SELECT STDDEV(num_distinct_cabg) AS std_dev
FROM patient_cabg;