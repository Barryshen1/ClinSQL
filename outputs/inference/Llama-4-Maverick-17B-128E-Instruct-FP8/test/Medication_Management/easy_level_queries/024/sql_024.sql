WITH patient_selection AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 84 AND 94
),
dapt_prescriptions AS (
  SELECT ps.subject_id, ps.hadm_id, ps.starttime, ps.stoptime, ps.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` ps
  INNER JOIN patient_selection p_sel
  ON ps.subject_id = p_sel.subject_id AND ps.hadm_id = p_sel.hadm_id
  WHERE LOWER(ps.drug) IN ('aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor')
),
dapt_duration AS (
  SELECT hadm_id, 
         MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_dapt_duration
  FROM (
    SELECT hadm_id, starttime, stoptime, drug,
           COUNT(DISTINCT LOWER(drug)) OVER (PARTITION BY hadm_id, starttime, stoptime) AS num_drugs
    FROM dapt_prescriptions
  ) subquery
  WHERE num_drugs >= 2
  GROUP BY hadm_id
)
SELECT MAX(max_dapt_duration) AS max_single_inpatient_dapt_duration
FROM dapt_duration;