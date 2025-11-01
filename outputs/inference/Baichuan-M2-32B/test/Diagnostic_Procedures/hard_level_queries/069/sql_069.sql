WITH pe_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND dd.icd_code IN ('D64.0', 'D64.9') -- Pulmonary embolism ICD-10 codes
    AND dd.icd_version = 10
),
first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN pe_admissions p
    ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),
icu_procedures AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    p.icd_code,  -- Corrected column name from procedure_icd to icd_code
    p.seq_num,
    p.chartdate
  FROM first_icu_stays f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id 
    AND f.hadm_id = p.hadm_id
    AND TIMESTAMP(p.chartdate) BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  WHERE f.rn = 1  -- Filter for first ICU stay
),
patient_procedure_counts AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count  -- Corrected to icd_code
  FROM icu_procedures
  GROUP BY subject_id, hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM patient_procedure_counts
),
final_data AS (
  SELECT 
    q.quintile,
    q.procedure_count,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM quintiles q
  INNER JOIN pe_admissions a
    ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
)
SELECT 
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(los_days) AS avg_los_days,
  100.0 * AVG(hospital_expire_flag) AS mortality_percent
FROM final_data
GROUP BY quintile
ORDER BY quintile;