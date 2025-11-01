WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.hospital_expire_flag = 0
),
first_icu_stays AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    i.stay_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY fa.subject_id, fa.hadm_id ORDER BY i.intime) AS stay_rn
  FROM 
    first_admissions fa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    fa.hadm_id = i.hadm_id
  WHERE 
    fa.rn = 1
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER() AS p25_icu_los_days
FROM 
  first_icu_stays
WHERE 
  stay_rn = 1;