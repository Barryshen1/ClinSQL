WITH first_icu_stay AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime, 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
hepatic_patients AS (
  SELECT 
    f.subject_id, 
    f.stay_id, 
    f.hadm_id, 
    f.intime, 
    f.outtime, 
    f.los, 
    a.hospital_expire_flag
  FROM first_icu_stay f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON f.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON f.subject_id = p.subject_id
  WHERE 
    f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.icd_code LIKE 'K72%'
    AND d.icd_version = 10
),
procedure_counts AS (
  SELECT 
    h.subject_id, 
    h.stay_id, 
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM hepatic_patients h
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON h.stay_id = pe.stay_id
  WHERE 
    pe.starttime BETWEEN h.intime AND DATETIME_ADD(h.intime, INTERVAL 72 HOUR)
  GROUP BY h.subject_id, h.stay_id
),
quartiles AS (
  SELECT 
    pc.subject_id, 
    pc.procedure_count, 
    h.los, 
    h.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
  FROM procedure_counts pc
  JOIN hepatic_patients h 
    ON pc.subject_id = h.subject_id AND pc.stay_id = h.stay_id
)
SELECT 
  quartile,
  COUNT(subject_id) AS num_patients,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(procedure_count) AS mean_procedures,
  AVG(los) AS mean_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;