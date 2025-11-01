WITH antiplatelet_drugs AS (
  SELECT 
    subject_id, 
    hadm_id, 
    drug,
    starttime,
    stoptime,
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%aspirin%' 
    OR LOWER(drug) LIKE '%asa%' 
    OR LOWER(drug) LIKE '%clopidogrel%' 
    OR LOWER(drug) LIKE '%plavix%' 
    OR LOWER(drug) LIKE '%prasugrel%' 
    OR LOWER(drug) LIKE '%effient%' 
    OR LOWER(drug) LIKE '%ticagrelor%' 
    OR LOWER(drug) LIKE '%brilinta%'
),
dapt_admissions AS (
  SELECT hadm_id
  FROM antiplatelet_drugs
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT drug) >= 2  -- At least two distinct antiplatelet drugs
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN dapt_admissions d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 44 AND 54
)
SELECT 
  STDDEV(ad.duration_days) AS sd_duration_days
FROM antiplatelet_drugs ad
INNER JOIN cohort c 
  ON ad.hadm_id = c.hadm_id 
  AND ad.subject_id = c.subject_id
WHERE ad.stoptime IS NOT NULL;  -- Exclude prescriptions without stop time;