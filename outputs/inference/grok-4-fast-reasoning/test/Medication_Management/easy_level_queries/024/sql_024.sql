WITH cohort AS (
  SELECT DISTINCT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    p.anchor_age, 
    p.anchor_year, 
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
aspirin_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE (LOWER(drug) LIKE '%aspirin%' OR LOWER(drug) LIKE '%acetylsalicylic%')
    AND hadm_id IS NOT NULL
),
p2y12_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE (LOWER(drug) LIKE '%clopidogrel%' 
         OR LOWER(drug) LIKE '%prasugrel%' 
         OR LOWER(drug) LIKE '%ticagrelor%')
    AND hadm_id IS NOT NULL
),
dapt_hadms AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort c
  INNER JOIN aspirin_hadms asp 
    ON c.subject_id = asp.subject_id AND c.hadm_id = asp.hadm_id
  INNER JOIN p2y12_hadms p2 
    ON c.subject_id = p2.subject_id AND c.hadm_id = p2.hadm_id
  WHERE EXTRACT(YEAR FROM c.admittime) - c.anchor_year + c.anchor_age BETWEEN 84 AND 94
)
SELECT 
  MAX(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS max_dapt_duration_days
FROM dapt_hadms dh
INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
  ON dh.subject_id = pr.subject_id AND dh.hadm_id = pr.hadm_id
WHERE (LOWER(pr.drug) LIKE '%clopidogrel%' 
       OR LOWER(pr.drug) LIKE '%prasugrel%' 
       OR LOWER(pr.drug) LIKE '%ticagrelor%')
  AND pr.stoptime IS NOT NULL
  AND pr.starttime < pr.stoptime;