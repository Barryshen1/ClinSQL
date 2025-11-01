WITH pe_patients AS (
  SELECT 
    d.subject_id, 
    d.hadm_id, 
    p.gender, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE 
    di.long_title LIKE '%pulmonary embolism%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),
icu_first_stay AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN pe_patients p 
    ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
),
procedure_count AS (
  SELECT 
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM icu_first_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND f.intime + INTERVAL '72' HOUR
  GROUP BY f.stay_id
),
admissions_data AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN icu_first_stay f 
    ON a.hadm_id = f.hadm_id
),
combined AS (
  SELECT 
    pc.procedure_count,
    ad.los_days,
    ad.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS quintile
  FROM procedure_count pc
  JOIN icu_first_stay f 
    ON pc.stay_id = f.stay_id
  JOIN admissions_data ad 
    ON f.hadm_id = ad.hadm_id
)
SELECT 
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(los_days) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM combined
GROUP BY quintile
ORDER BY quintile;