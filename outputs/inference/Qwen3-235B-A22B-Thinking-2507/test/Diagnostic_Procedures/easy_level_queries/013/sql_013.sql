WITH target_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
),
valve_procedures AS (
  SELECT 
    ta.hadm_id,
    p_icd.icd_code
  FROM target_admissions ta
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    ON ta.hadm_id = p_icd.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON p_icd.icd_code = d_proc.icd_code 
    AND p_icd.icd_version = d_proc.icd_version
  WHERE LOWER(d_proc.long_title) LIKE '%valve%'
    AND (LOWER(d_proc.long_title) LIKE '%repair%' OR LOWER(d_proc.long_title) LIKE '%replacement%')
),
hadm_valve_count AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS count_valve
  FROM valve_procedures
  GROUP BY hadm_id
)
SELECT MIN(count_valve) AS min_valve_procedures
FROM hadm_valve_count;