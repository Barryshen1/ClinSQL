WITH first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
),
pneumonia_patients AS (
  SELECT DISTINCT
    d.subject_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE 
    LOWER(d_icd.long_title) LIKE '%pneumonia%'
),
eligible_patients AS (
  SELECT 
    p.subject_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
)
SELECT 
  APPROX_QUANTILES(fis.los, 1000)[OFFSET(250)] AS p25_icu_los_days
FROM 
  first_icu_stay fis
JOIN 
  pneumonia_patients pp
  ON fis.subject_id = pp.subject_id
JOIN 
  eligible_patients ep
  ON fis.subject_id = ep.subject_id
WHERE 
  fis.rn = 1;