WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
hf_admissions AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '428%') 
             OR (icd_version = 10 AND icd_code LIKE 'I50%') 
          THEN 1 ELSE 0 
        END) AS heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
lab_abnormal AS (
  SELECT 
    le.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN base_admissions ba 
    ON le.hadm_id = ba.hadm_id
  WHERE 
    le.charttime BETWEEN ba.admittime AND DATETIME_ADD(ba.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'critically abnormal'
  GROUP BY le.hadm_id
),
combined_table AS (
  SELECT 
    ba.*,
    COALESCE(hf.heart_failure, 0) AS heart_failure,
    COALESCE(la.lab_instability_score, 0) AS lab_instability_score,
    DATETIME_DIFF(ba.dischtime, ba.admittime, DAY) AS los_days
  FROM base_admissions ba
  LEFT JOIN hf_admissions hf
    ON ba.hadm_id = hf.hadm_id
  LEFT JOIN lab_abnormal la
    ON ba.hadm_id = la.hadm_id
)
SELECT 
  'Heart Failure' AS cohort,
  MAX(lab_instability_score) AS max_lab_instability_score,
  AVG(lab_instability_score) AS critical_event_rate,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM combined_table
WHERE heart_failure = 1
UNION ALL
SELECT 
  'General Inpatients' AS cohort,
  MAX(lab_instability_score) AS max_lab_instability_score,
  AVG(lab_instability_score) AS critical_event_rate,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM combined_table;