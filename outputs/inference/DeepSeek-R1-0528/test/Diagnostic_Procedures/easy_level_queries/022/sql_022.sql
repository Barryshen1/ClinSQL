WITH filtered_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),
pacemaker_icd_procedures AS (
  SELECT 
    proc.hadm_id,
    proc.icd_code,
    proc.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
    ON proc.icd_code = di.icd_code 
    AND proc.icd_version = di.icd_version
  WHERE 
    (di.long_title LIKE '%pacemaker%' OR di.long_title LIKE '%defibrillator%')
    AND (di.long_title LIKE '%insertion%' OR di.long_title LIKE '%implant%')
    AND di.long_title NOT LIKE '%removal%'
),
procedure_counts AS (
  SELECT 
    fa.hadm_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '_', proc.icd_version)) AS num_procedures
  FROM filtered_admissions fa
  INNER JOIN pacemaker_icd_procedures proc
    ON fa.hadm_id = proc.hadm_id
  GROUP BY fa.hadm_id
)
SELECT 
  MIN(num_procedures) AS min_num_procedures
FROM procedure_counts;