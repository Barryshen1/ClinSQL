WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 57 AND 67
)
SELECT MIN(procedure_count) AS min_distinct_valve_procedures_per_hospitalization
FROM (
  SELECT p.subject_id, COUNT(DISTINCT p.hadm_id) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN cohort c ON p.subject_id = c.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%valve%'
  GROUP BY p.subject_id
) sub;