WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
dapt_flag AS (
  SELECT 
    fa.hadm_id,
    fa.hospital_expire_flag,
    MAX(CASE WHEN 
            LOWER(pres.drug) LIKE '%aspirin%' 
            OR LOWER(pres.drug) LIKE '%acetylsalicylic%' 
            OR LOWER(pres.drug) LIKE '%asa%' 
         THEN 1 ELSE 0 END) AS has_aspirin,
    MAX(CASE WHEN 
            LOWER(pres.drug) LIKE '%clopidogrel%' 
            OR LOWER(pres.drug) LIKE '%prasugrel%' 
            OR LOWER(pres.drug) LIKE '%ticagrelor%' 
         THEN 1 ELSE 0 END) AS has_p2y12
  FROM first_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON fa.hadm_id = pres.hadm_id
    AND pres.starttime < fa.dischtime
    AND (pres.stoptime IS NULL OR pres.stoptime > fa.admittime)
  GROUP BY fa.hadm_id, fa.hospital_expire_flag
),
dapt_cohort AS (
  SELECT 
    hospital_expire_flag
  FROM dapt_flag
  WHERE has_aspirin = 1 AND has_p2y12 = 1
)
SELECT 
  SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag))) AS sd_mortality
FROM dapt_cohort;