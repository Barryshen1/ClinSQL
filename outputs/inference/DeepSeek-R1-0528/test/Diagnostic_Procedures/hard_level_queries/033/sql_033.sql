WITH pneumonia_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- ICD-9: 480-486, 487.0
    (icd_version = 9 AND (
        REGEXP_CONTAINS(icd_code, r'^(480|481|482|483|484|485|486)') OR 
        icd_code IN ('4870', '487.0')
    )) OR 
    -- ICD-10: J12-J18, J10.0, J11.0
    (icd_version = 10 AND (
        REGEXP_CONTAINS(icd_code, r'^J1[012345678]') OR 
        icd_code IN ('J100', 'J110', 'J10.0', 'J11.0')
    ))
),
first_icu_stay AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE ie.stay_id = (
    SELECT MIN(stay_id)
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2
    WHERE ie2.subject_id = ie.subject_id
  )
),
cohort AS (
  SELECT 
    fis.subject_id, 
    fis.hadm_id, 
    fis.stay_id,
    fis.intime,
    fis.los
  FROM first_icu_stay fis
  INNER JOIN pneumonia_patients pp
    ON fis.hadm_id = pp.hadm_id
  WHERE 
    fis.gender = 'M'
    AND (fis.anchor_age + (EXTRACT(YEAR FROM fis.intime) - fis.anchor_year)) 
        BETWEEN 37 AND 47
),
procedure_counts AS (
  SELECT 
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.intime 
        AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
cohort_with_outcomes AS (
  SELECT 
    c.stay_id,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    c.los,
    adm.hospital_expire_flag
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.stay_id = pc.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.hadm_id = adm.hadm_id
),
quintiles AS (
  SELECT 
    stay_id,
    procedure_count,
    los,
    hospital_expire_flag,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM cohort_with_outcomes
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quintiles
GROUP BY quintile
ORDER BY quintile;