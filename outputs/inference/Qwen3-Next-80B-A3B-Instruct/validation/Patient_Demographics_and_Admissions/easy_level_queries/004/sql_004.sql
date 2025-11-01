WITH first_admission AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn_admission
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 70 AND 80
),
aki_diagnoses AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi
    ON di.icd_code = ddi.icd_code 
    AND di.icd_version = ddi.icd_version
  WHERE 
    di.icd_version = 10
    AND (
      LOWER(ddi.long_title) LIKE '%acute kidney injury%' 
      OR di.icd_code LIKE 'N17%'
    )
),
first_icu_stay AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn_icu
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
)
SELECT 
  STDDEV(los) AS sd_length_of_stay_days
FROM 
  first_admission fa
INNER JOIN 
  aki_diagnoses aki
  ON fa.subject_id = aki.subject_id 
  AND fa.hadm_id = aki.hadm_id
INNER JOIN 
  first_icu_stay fis
  ON fa.hadm_id = fis.hadm_id
  AND fis.rn_icu = 1
WHERE 
  fa.rn_admission = 1;