WITH valve_procedures AS (
  SELECT 
    p.subject_id,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON a.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replace%')
    AND (
      pat.anchor_age - (pat.anchor_year - EXTRACT(YEAR FROM a.admittime))
    ) BETWEEN 42 AND 52
)
SELECT 
  AVG(procedure_count) AS avg_distinct_valve_procedures_per_patient
FROM (
  SELECT 
    subject_id, 
    COUNT(DISTINCT icd_code) AS procedure_count
  FROM valve_procedures
  GROUP BY subject_id
) AS counts;