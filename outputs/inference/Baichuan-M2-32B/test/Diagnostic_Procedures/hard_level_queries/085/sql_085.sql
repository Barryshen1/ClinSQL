WITH first_icu_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime, 
    outtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
diagnosis_filter AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%lower gi bleeding%'
     OR LOWER(dd.long_title) LIKE '%lower gastrointestinal hemorrhage%'
),
icu_adm AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE f.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
icu_adm_with_diagnosis AS (
  SELECT 
    i.*
  FROM icu_adm i
  JOIN diagnosis_filter d
    ON i.subject_id = d.subject_id
    AND i.hadm_id = d.hadm_id
),
procedures_48h AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN icu_adm_with_diagnosis i
    ON p.subject_id = i.subject_id
    AND p.hadm_id = i.hadm_id
  WHERE p.chartdate >= DATE(i.intime)
    AND p.chartdate <= DATE(DATETIME_ADD(i.intime, INTERVAL 48 HOUR))
  GROUP BY p.subject_id, p.hadm_id
),
patient_data AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.hospital_expire_flag,
    COALESCE(p.distinct_procedure_count, 0) AS distinct_procedure_count,
    (UNIX_SECONDS(TIMESTAMP(i.outtime)) - UNIX_SECONDS(TIMESTAMP(i.intime))) / (24 * 3600) AS los_days
  FROM icu_adm_with_diagnosis i
  LEFT JOIN procedures_48h p
    ON i.subject_id = p.subject_id
    AND i.hadm_id = p.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY distinct_procedure_count) AS quintile
  FROM patient_data
)
SELECT 
  quintile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;