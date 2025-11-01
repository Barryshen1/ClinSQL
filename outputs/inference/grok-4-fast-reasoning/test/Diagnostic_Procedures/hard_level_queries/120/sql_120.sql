WITH first_icu AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE intime IS NOT NULL
),
first_stays AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM first_icu
  WHERE rn = 1
),
cohort AS (
  SELECT 
    fs.subject_id, 
    fs.hadm_id, 
    fs.stay_id, 
    fs.intime,
    p.gender, 
    p.anchor_age,
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fs.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fs.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),
uGI_cohort AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.stay_id, 
    c.intime,
    c.gender, 
    c.anchor_age,
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON c.hadm_id = di.hadm_id AND di.seq_num = 1
  WHERE 
    (
      (di.icd_version = 9 AND (
        di.icd_code = '578.0' OR 
        di.icd_code LIKE '53%' OR 
        di.icd_code LIKE '535.%' OR
        di.icd_code IN ('530.7', '530.82', '537.83')
      ))
      OR
      (di.icd_version = 10 AND (
        di.icd_code LIKE 'K25%' OR 
        di.icd_code LIKE 'K26%' OR 
        di.icd_code LIKE 'K27%' OR
        di.icd_code IN ('K92.0', 'K92.2')
      ))
    )
),
diag_intensity AS (
  SELECT 
    ug.subject_id, 
    ug.hadm_id,
    COUNT(le.labevent_id) AS diag_intensity
  FROM uGI_cohort ug
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ug.subject_id = le.subject_id
    AND ug.hadm_id = le.hadm_id
    AND le.charttime >= ug.intime
    AND le.charttime < TIMESTAMP_ADD(ug.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY ug.subject_id, ug.hadm_id
),
proc_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
with_quartile AS (
  SELECT 
    di.*,
    ug.admittime,
    ug.dischtime,
    ug.hospital_expire_flag,
    pc.procedure_count,
    NTILE(4) OVER (ORDER BY di.diag_intensity ASC) AS quartile
  FROM diag_intensity di
  JOIN uGI_cohort ug 
    ON di.subject_id = ug.subject_id AND di.hadm_id = ug.hadm_id
  LEFT JOIN proc_counts pc 
    ON di.hadm_id = pc.hadm_id
)
SELECT 
  quartile,
  ROUND(AVG(COALESCE(procedure_count, 0)), 2) AS mean_procedure_count,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;