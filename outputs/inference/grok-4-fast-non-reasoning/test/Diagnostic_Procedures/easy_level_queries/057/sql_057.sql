WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),
cardiac_cath_procs AS (
  SELECT pi.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN eligible_patients ep ON pi.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%cardiac catheterization%'
)
SELECT MIN(proc_count) AS min_procedures_per_patient
FROM (
  SELECT subject_id, COUNT(*) AS proc_count
  FROM cardiac_cath_procs
  GROUP BY subject_id
);