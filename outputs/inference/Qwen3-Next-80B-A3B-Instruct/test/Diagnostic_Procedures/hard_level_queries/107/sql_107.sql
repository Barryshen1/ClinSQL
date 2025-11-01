WITH pe_patients AS (
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON p.subject_id = di.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(dicd.long_title) LIKE '%pulmonary embolism%'
),

first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN pe_patients pe ON i.subject_id = pe.subject_id
),

first_icu_with_procedures AS (
  SELECT 
    fis.subject_id,
    fis.stay_id,
    fis.intime,
    fis.los,
    COUNT(*) AS procedure_count
  FROM first_icu_stay fis
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE di.label IN (
    'CT PULMONARY ANGI',
    'CT ANGI',
    'CT ANGIOGRAM',
    'CT ANGIOGRAPHY',
    'VENTILATION/PERFUSION SCAN',
    'PULMONARY ANGIOGRAPHY',
    'ULTRASOUND',
    'DOPPLER ULTRASOUND',
    'V/Q SCAN',
    'PULMONARY ANGI',
    'CT ANGIOGRAPHY - PULMONARY',
    'CT PULMONARY ANGIOGRAM',
    'PULMONARY ANGIOGRAM',
    'VENTILATION PERFUSION SCAN',
    'CT ANGIOGRAPHY PULMONARY'
  )
  GROUP BY fis.subject_id, fis.stay_id, fis.intime, fis.los
),

quartiles AS (
  SELECT 
    subject_id,
    procedure_count,
    los,
    NTILE(4) OVER (ORDER BY procedure_count) AS procedure_quartile
  FROM first_icu_with_procedures
)

SELECT 
  procedure_quartile,
  COUNT(*) AS N,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM quartiles q
INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON q.subject_id = a.subject_id
GROUP BY procedure_quartile
ORDER BY procedure_quartile;