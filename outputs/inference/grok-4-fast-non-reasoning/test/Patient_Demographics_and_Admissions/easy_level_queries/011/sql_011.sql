WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 76 AND 86
    AND p.gender = 'M'
    AND a.hospital_expire_flag = 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.hadm_id) = 1
),
dapt_patients AS (
  SELECT DISTINCT fa.subject_id
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON fa.hadm_id = pres.hadm_id
    AND pres.starttime <= fa.dischtime
  WHERE (LOWER(pres.drug) LIKE '%aspirin%'
         OR LOWER(pres.drug) LIKE '%acetylsalicylic%')
     OR (LOWER(pres.drug) LIKE '%clopidogrel%'
         OR LOWER(pres.drug) LIKE '%prasugrel%'
         OR LOWER(pres.drug) LIKE '%ticagrelor%'
         OR LOWER(pres.drug) LIKE '%plavix%'
         OR LOWER(pres.drug) LIKE '%effient%'
         OR LOWER(pres.drug) LIKE '%brilinta%')
  QUALIFY COUNTIF(LOWER(pres.drug) LIKE '%aspirin%' OR LOWER(pres.drug) LIKE '%acetylsalicylic%') OVER (PARTITION BY fa.subject_id) >= 1
     AND COUNTIF(LOWER(pres.drug) LIKE '%clopidogrel%' OR LOWER(pres.drug) LIKE '%prasugrel%' OR LOWER(pres.drug) LIKE '%ticagrelor%'
                 OR LOWER(pres.drug) LIKE '%plavix%' OR LOWER(pres.drug) LIKE '%effient%' OR LOWER(pres.drug) LIKE '%brilinta%') OVER (PARTITION BY fa.subject_id) >= 1
)
SELECT 
  AVG(icu.los) AS avg_icu_los_days
FROM dapt_patients dp
INNER JOIN first_admissions fa
  ON dp.subject_id = fa.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON fa.hadm_id = icu.hadm_id
WHERE icu.los > 0;