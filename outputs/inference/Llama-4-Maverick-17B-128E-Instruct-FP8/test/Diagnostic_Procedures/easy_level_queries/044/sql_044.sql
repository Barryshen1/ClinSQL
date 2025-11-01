WITH patient_subset AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 56 AND 66
),
mcs_procedures AS (
  SELECT pe.subject_id, COUNT(DISTINCT pe.itemid) as num_mcs_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ECMO%' OR di.label LIKE '%LVAD%' OR di.label LIKE '%RVAD%' OR di.label LIKE '%Mechanical Circulatory Support%'
  AND pe.subject_id IN (SELECT subject_id FROM patient_subset)
  GROUP BY pe.subject_id
)
SELECT STDDEV(num_mcs_procedures) as sd_mcs_procedures
FROM mcs_procedures;