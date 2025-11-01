WITH valve_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%valve%' AND 
    (LOWER(long_title) LIKE '%repair%' OR LOWER(long_title) LIKE '%replacement%')
),
filtered_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F' AND 
    pat.anchor_age - pat.anchor_year + EXTRACT(YEAR FROM adm.admittime) BETWEEN 57 AND 67
),
procedure_counts AS (
  SELECT 
    adm.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_valve_procedures
  FROM filtered_admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
  INNER JOIN valve_procedures vp
    ON proc.icd_code = vp.icd_code AND proc.icd_version = vp.icd_version
  GROUP BY adm.hadm_id
)
SELECT 
  MIN(num_valve_procedures) AS min_valve_procedures
FROM procedure_counts;