WITH admissions_filtered AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
),
mech_circ_support AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE linksto = 'procedureevents'
    AND (
      label LIKE '%ECMO%' 
      OR label LIKE '%extracorporeal%' 
      OR label LIKE '%membrane oxygenation%' 
      OR label LIKE '%IABP%' 
      OR label LIKE '%intra-aortic balloon%' 
      OR label LIKE '%impella%'
    )
),
procedures_in_age_group AS (
  SELECT 
    af.subject_id,
    pe.itemid
  FROM admissions_filtered af
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON af.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON i.stay_id = pe.stay_id
  INNER JOIN mech_circ_support mcs
    ON pe.itemid = mcs.itemid
),
patient_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT itemid) AS distinct_procedure_count
  FROM procedures_in_age_group
  GROUP BY subject_id
)
SELECT MIN(distinct_procedure_count) AS min_distinct_procedures
FROM patient_counts;