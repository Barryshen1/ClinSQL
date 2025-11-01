WITH target_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
),

mcs_procedures_icu AS (
  SELECT pe.subject_id, pe.itemid AS procedure_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ECMO%'
     OR di.label LIKE '%IABP%'
     OR di.label LIKE '%LVAD%'
     OR di.label LIKE '%TandemHeart%'
     OR di.label LIKE '%CentriMag%'
     OR di.label LIKE '%Impella%'
     OR di.label LIKE '%VAD%'
     OR di.label LIKE '%mechanical circulatory support%'
),

mcs_procedures_hosp AS (
  SELECT pi.subject_id, pi.icd_code AS procedure_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE dip.long_title LIKE '%ECMO%'
     OR dip.long_title LIKE '%Intra-aortic Balloon Pump%'
     OR dip.long_title LIKE '%Left Ventricular Assist Device%'
     OR dip.long_title LIKE '%TandemHeart%'
     OR dip.long_title LIKE '%CentriMag%'
     OR dip.long_title LIKE '%Impella%'
     OR dip.long_title LIKE '%VAD%'
     OR dip.long_title LIKE '%mechanical circulatory support%'
),

all_mcs_procedures AS (
  SELECT subject_id, procedure_id FROM mcs_procedures_icu
  UNION ALL
  SELECT subject_id, procedure_id FROM mcs_procedures_hosp
),

patient_procedure_counts AS (
  SELECT 
    subject_id, 
    COUNT(DISTINCT procedure_id) AS num_procedures
  FROM all_mcs_procedures
  WHERE subject_id IN (SELECT subject_id FROM target_patients)
  GROUP BY subject_id
)

SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_procedures) AS percentile_25
FROM patient_procedure_counts;