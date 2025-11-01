WITH pneumonia_patients AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE d.long_title LIKE '%pneumonia%'
),
first_icu_stay AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.icu_los_days,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_icu_stay f
    ON p.subject_id = f.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON f.hadm_id = adm.hadm_id
  INNER JOIN pneumonia_patients pp
    ON p.subject_id = pp.subject_id AND f.hadm_id = pp.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND f.stay_seq = 1
),
procedures_first_48h AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.stay_id
),
quintiles AS (
  SELECT 
    subject_id,
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedures_first_48h
)
SELECT 
  q.quintile,
  COUNT(*) AS patient_count,
  AVG(q.procedure_count) AS mean_procedure_count,
  AVG(c.icu_los_days) AS mean_icu_los_days,
  AVG(c.hospital_expire_flag) AS hospital_mortality_rate
FROM quintiles q
INNER JOIN cohort c
  ON q.subject_id = c.subject_id AND q.stay_id = c.stay_id
GROUP BY q.quintile
ORDER BY q.quintile;