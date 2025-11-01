WITH first_cabg_admission AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a 
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi 
    ON a.hadm_id = pi.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND LOWER(dip.long_title) LIKE '%coronary artery bypass graft%'
),
icu_los_per_admission AS (
  SELECT 
    fca.hadm_id,
    SUM(i.los) AS total_icu_los_days
  FROM 
    first_cabg_admission fca
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i 
    ON fca.hadm_id = i.hadm_id
  WHERE 
    fca.rn = 1
  GROUP BY 
    fca.hadm_id
)
SELECT 
  AVG(total_icu_los_days) AS mean_icu_los_days
FROM 
  icu_los_per_admission;