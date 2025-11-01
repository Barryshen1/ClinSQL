SELECT MAX(procedure_count) AS max_distinct_echocardiography_count
FROM (
  SELECT p.subject_id, COUNT(DISTINCT d_icd.icd_code) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    ON p.subject_id = proc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_icd
    ON proc.icd_code = d_icd.icd_code AND proc.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(d_icd.long_title) LIKE '%echocardiography%'
  GROUP BY p.subject_id
) subquery;