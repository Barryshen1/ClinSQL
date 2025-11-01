WITH heart_failure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR
    (icd_version = 10 AND icd_code LIKE 'I50%')
),

hf_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM heart_failure_codes hfc
      WHERE diag.icd_code = hfc.icd_code
        AND diag.icd_version = hfc.icd_version
    )
),

control_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM hf_cohort)
),

labs_in_first_72h AS (
  SELECT 
    lab.hadm_id,
    lab.itemid,
    lab.charttime,
    lab.flag,
    dlab.category
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON lab.itemid = dlab.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON lab.hadm_id = adm.hadm_id
  WHERE 
    lab.charttime <= DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND lab.flag IS NOT NULL
    AND lab.flag != 'Normal'
),

instability_score AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT category) AS num_critical_lab_types
  FROM labs_in_first_72h
  GROUP BY hadm_id
),

hf_with_stats AS (
  SELECT 
    hf.hadm_id,
    COALESCE(iscore.num_critical_lab_types, 0) AS instability_score,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    adm.hospital_expire_flag
  FROM hf_cohort hf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON hf.hadm_id = adm.hadm_id
  LEFT JOIN instability_score iscore
    ON hf.hadm_id = iscore.hadm_id
),

control_with_stats AS (
  SELECT 
    ctrl.hadm_id,
    COALESCE(iscore.num_critical_lab_types, 0) AS instability_score,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    adm.hospital_expire_flag
  FROM control_cohort ctrl
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ctrl.hadm_id = adm.hadm_id
  LEFT JOIN instability_score iscore
    ON ctrl.hadm_id = iscore.hadm_id
)

SELECT 
  'Heart Failure' AS cohort,
  COUNT(hadm_id) AS num_admissions,
  AVG(instability_score) AS avg_instability_score,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM hf_with_stats

UNION ALL

SELECT 
  'Control' AS cohort,
  COUNT(hadm_id) AS num_admissions,
  AVG(instability_score) AS avg_instability_score,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM control_with_stats;