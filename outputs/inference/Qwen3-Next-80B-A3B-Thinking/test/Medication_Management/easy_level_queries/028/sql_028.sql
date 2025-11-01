WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),
admissions_for_female AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients fp ON a.subject_id = fp.subject_id
),
antiplatelet_drugs AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    'Aspirin', 'ASA', 'Acetylsalicylic Acid', 'Clopidogrel', 'Plavix', 
    'Ticagrelor', 'Brilinta', 'Prasugrel', 'Effient', 'Dipyridamole', 
    'Persantine', 'Cilostazol', 'Pletal'
  )
),
dapt_patients AS (
  SELECT a.hadm_id, a.subject_id
  FROM admissions_for_female a
  JOIN antiplatelet_drugs ap ON a.hadm_id = ap.hadm_id AND a.subject_id = ap.subject_id
  GROUP BY a.hadm_id, a.subject_id
  HAVING COUNT(DISTINCT ap.drug) >= 2
),
dapt_prescriptions AS (
  SELECT 
    DATE_DIFF(ap.stoptime, ap.starttime, DAY) AS duration_days
  FROM antiplatelet_drugs ap
  JOIN dapt_patients dp ON ap.hadm_id = dp.hadm_id AND ap.subject_id = dp.subject_id
  WHERE ap.stoptime IS NOT NULL
)
SELECT STDDEV(duration_days) AS sd_duration
FROM dapt_prescriptions;