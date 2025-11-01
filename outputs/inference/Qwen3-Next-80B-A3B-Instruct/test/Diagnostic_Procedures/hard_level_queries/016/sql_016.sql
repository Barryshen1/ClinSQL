WITH first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.stay_id IN (
    SELECT stay_id
    FROM (
      SELECT stay_id, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    )
    WHERE rn = 1
  )
),
pneumonia_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_icu_stay fis ON p.subject_id = fis.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      did.icd_code LIKE 'J12%' OR did.icd_code LIKE 'J13%' OR did.icd_code LIKE 'J14%' OR 
      did.icd_code LIKE 'J15%' OR did.icd_code LIKE 'J16%' OR did.icd_code LIKE 'J17%' OR 
      did.icd_code LIKE 'J18%' OR did.icd_code = '486'
    )
),
diagnostic_procedures AS (
  SELECT 
    pe.stay_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  INNER JOIN first_icu_stay fis ON pe.stay_id = fis.stay_id
  INNER JOIN pneumonia_patients pp ON fis.subject_id = pp.subject_id
  WHERE di.label IN (
    'Chest X-ray', 'CT Head', 'CT Chest', 'CT Abdomen', 'Ultrasound Abdomen', 'Ultrasound Chest',
    'Blood Culture', 'Sputum Culture', 'Urine Culture', 'Bronchoalveolar Lavage', 'Lumbar Puncture',
    'Pleural Fluid Culture', 'CSF Culture', 'Wound Culture', 'Arterial Blood Gas', 'Venous Blood Gas',
    'Blood Gas', 'CXR', 'Chest X-ray (AP)', 'Chest X-ray (Lateral)', 'Chest X-ray (PA)',
    'Chest X-ray (AP/Lat)', 'Chest X-ray (PA/Lat)'
  )
    AND pe.starttime >= fis.intime
    AND pe.starttime <= TIMESTAMP_ADD(fis.intime, INTERVAL 72 HOUR)
  GROUP BY pe.stay_id
),
quintiles AS (
  SELECT 
    dp.proc_count,
    fis.los,
    a.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY dp.proc_count) AS quintile
  FROM diagnostic_procedures dp
  INNER JOIN first_icu_stay fis ON dp.stay_id = fis.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.subject_id = a.subject_id
)
SELECT 
  quintile,
  AVG(proc_count) AS avg_procedure_count,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag * 1.0) * 100 AS in_hospital_mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;