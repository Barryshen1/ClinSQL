WITH patients_44_54_female AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 44 AND 54
),
dapt_patients AS (
  SELECT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patients_44_54_female pf ON p.subject_id = pf.subject_id
  WHERE LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%clopidogrel%' 
  OR LOWER(p.drug) LIKE '%ticagrelor%' OR LOWER(p.drug) LIKE '%prasugrel%'
),
single_antiplatelet_duration AS (
  SELECT dp.hadm_id, 
         SUM(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS total_duration
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN dapt_patients dp ON p.hadm_id = dp.hadm_id
  WHERE (LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%clopidogrel%' 
         OR LOWER(p.drug) LIKE '%ticagrelor%' OR LOWER(p.drug) LIKE '%prasugrel%')
  AND p.subject_id IN (SELECT subject_id FROM dapt_patients)
  GROUP BY dp.hadm_id
  HAVING COUNT(DISTINCT LOWER(p.drug)) = 1
)
SELECT STDDEV(total_duration) AS sd_duration
FROM single_antiplatelet_duration;