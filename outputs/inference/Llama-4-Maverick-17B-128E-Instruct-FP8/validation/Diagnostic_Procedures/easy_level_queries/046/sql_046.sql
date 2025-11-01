WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 80 AND 90
),
mcs_procedures AS (
  SELECT DISTINCT i.stay_id, pe.itemid
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON i.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ECMO%' OR di.label LIKE '%IABP%' OR di.label LIKE '%Mechanical Circulatory Support%'
),
count_mcs_procedures AS (
  SELECT pa.hadm_id, COUNT(DISTINCT mp.itemid) as num_mcs_procedures
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON pa.hadm_id = i.hadm_id
  JOIN mcs_procedures mp ON i.stay_id = mp.stay_id
  GROUP BY pa.hadm_id
)

SELECT MAX(num_mcs_procedures) as max_mcs_procedures
FROM count_mcs_procedures;