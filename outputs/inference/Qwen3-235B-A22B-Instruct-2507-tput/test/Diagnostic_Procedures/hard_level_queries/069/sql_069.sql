WITH patient_pe AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND LOWER(d.long_title) LIKE '%pulmonary embolism%'
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patient_pe pp ON i.subject_id = pp.subject_id
),
first_icu_stay_filtered AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),
procedures_72h AS (
  SELECT 
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM first_icu_stay_filtered f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe 
    ON f.stay_id = pe.stay_id 
    AND pe.starttime >= f.intime 
    AND pe.starttime <= f.intime + INTERVAL '72' HOUR
  GROUP BY f.stay_id, f.subject_id, f.hadm_id
),
quintiles AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    distinct_procedure_count,
    NTILE(5) OVER (ORDER BY distinct_procedure_count) AS quintile
  FROM procedures_72h
),
outcomes AS (
  SELECT 
    q.quintile,
    AVG(q.distinct_procedure_count) AS avg_procedure_count,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS avg_hospital_los_days,
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM quintiles q
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON q.hadm_id = a.hadm_id
  GROUP BY q.quintile
)
SELECT 
  quintile,
  ROUND(avg_procedure_count, 2) AS avg_procedure_count,
  ROUND(avg_hospital_los_days, 2) AS avg_hospital_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_percent
FROM outcomes
ORDER BY quintile;