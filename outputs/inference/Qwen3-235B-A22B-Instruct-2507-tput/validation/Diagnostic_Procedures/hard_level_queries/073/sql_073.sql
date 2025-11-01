WITH first_icu_stay AS (
  SELECT 
    stay.subject_id,
    stay.hadm_id,
    stay.stay_id,
    stay.intime,
    stay.outtime,
    stay.los,
    ROW_NUMBER() OVER (PARTITION BY stay.subject_id ORDER BY stay.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stay
),
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
hepatic_diagnosis AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%hepatic failure%'
),
first_stay_with_diag AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM first_icu_stay f
  INNER JOIN patients_filtered p ON f.subject_id = p.subject_id
  INNER JOIN hepatic_diagnosis h ON f.hadm_id = h.hadm_id
  WHERE f.rn = 1
),
procedures_72h AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM first_stay_with_diag f
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id
  WHERE p.starttime >= f.intime
    AND p.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND LOWER(p.ordercategoryname) = 'diagnostic'
    AND p.statusdescription = 'Completed'  -- Only completed procedures
  GROUP BY p.subject_id
),
quartiles AS (
  SELECT 
    subject_id,
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedures_72h
)
SELECT
  q.quartile,
  COUNT(*) AS num_patients,
  MIN(q.procedure_count) AS min_procedures,
  MAX(q.procedure_count) AS max_procedures,
  AVG(q.procedure_count) AS mean_procedures,
  AVG(f.los) AS mean_los_days,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM quartiles q
JOIN first_stay_with_diag f ON q.subject_id = f.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;