WITH first_icu_stay AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p 
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d 
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic 
    ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(dic.long_title) LIKE '%hepatic%'
    AND LOWER(dic.long_title) LIKE '%failure%'
    AND LOWER(dic.long_title) NOT LIKE '%transplant%'
    AND LOWER(dic.long_title) NOT LIKE '%cirrhosis%' -- optional: if we want acute failure only, but question says "hepatic failure" broadly
),

-- Count diagnostic procedures in first 72 hours for each patient
procedures_in_72h AS (
  SELECT 
    fis.subject_id,
    COUNT(pe.itemid) AS procedure_count
  FROM first_icu_stay fis
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe 
    ON fis.stay_id = pe.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di 
    ON pe.itemid = di.itemid
  WHERE pe.starttime >= fis.intime
    AND pe.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
    AND pe.starttime IS NOT NULL
    AND (
      LOWER(di.category) = 'diagnostic'
      OR LOWER(di.label) LIKE '%diagnostic%'
      OR LOWER(di.label) LIKE '%exam%'
      OR LOWER(di.label) LIKE '%ultrasound%'
      OR LOWER(di.label) LIKE '%ct%'
      OR LOWER(di.label) LIKE '%mri%'
      OR LOWER(di.label) LIKE '%x-ray%'
      OR LOWER(di.label) LIKE '%echo%'
      OR LOWER(di.label) LIKE '%liver%'
      OR LOWER(di.label) LIKE '%hepatic%'
    )
  GROUP BY fis.subject_id
),

-- Assign quartiles based on procedure count
quartiles AS (
  SELECT 
    pis.subject_id,
    pis.procedure_count,
    NTILE(4) OVER (ORDER BY pis.procedure_count) AS procedure_quartile,
    fis.los,
    a.hospital_expire_flag
  FROM procedures_in_72h pis
  INNER JOIN first_icu_stay fis ON pis.subject_id = fis.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON fis.hadm_id = a.hadm_id
)

SELECT 
  procedure_quartile,
  COUNT(*) AS num_patients,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(procedure_count) AS mean_procedures,
  AVG(los) AS mean_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS in_hospital_mortality_pct
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;