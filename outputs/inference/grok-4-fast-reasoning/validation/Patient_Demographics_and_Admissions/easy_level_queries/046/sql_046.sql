WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) = 1
)
SELECT 
  STDDEV(hospital_expire_flag) AS sd_inhospital_mortality
FROM 
  first_admissions fa
WHERE 
  fa.gender = 'M'
  AND fa.anchor_age BETWEEN 37 AND 47
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres_aspirin
    WHERE 
      pres_aspirin.subject_id = fa.subject_id
      AND pres_aspirin.hadm_id = fa.hadm_id
      AND pres_aspirin.starttime >= fa.admittime
      AND pres_aspirin.starttime < fa.dischtime
      AND LOWER(pres_aspirin.drug) LIKE '%aspirin%'
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres_p2y12
    WHERE 
      pres_p2y12.subject_id = fa.subject_id
      AND pres_p2y12.hadm_id = fa.hadm_id
      AND pres_p2y12.starttime >= fa.admittime
      AND pres_p2y12.starttime < fa.dischtime
      AND LOWER(pres_p2y12.drug) IN (
        'clopidogrel', 
        'prasugrel', 
        'ticagrelor', 
        'ticlopidine', 
        'cangrelor'
      )
  );