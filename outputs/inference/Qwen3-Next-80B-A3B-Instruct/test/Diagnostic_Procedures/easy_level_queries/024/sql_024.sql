WITH coronary_procedures AS (
  -- ICD procedures from HOSP module (remove DISTINCT to count each procedure)
  SELECT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%angiography%'
     OR LOWER(d.long_title) LIKE '%pci%'
     OR LOWER(d.long_title) LIKE '%percutaneous coronary intervention%'
  
  UNION ALL
  
  -- ICU procedure events (remove DISTINCT)
  SELECT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON p.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.stay_id = i.stay_id
  WHERE LOWER(d.label) LIKE '%angiography%'
     OR LOWER(d.label) LIKE '%pci%'
     OR LOWER(d.label) LIKE '%percutaneous coronary intervention%'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
procedures_per_admission AS (
  SELECT cp.hadm_id, COUNT(*) AS procedure_count
  FROM coronary_procedures cp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON cp.hadm_id = a.hadm_id
  JOIN filtered_patients fp 
    ON a.subject_id = fp.subject_id
  GROUP BY cp.hadm_id
)
SELECT APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75_procedure_count
FROM procedures_per_admission;