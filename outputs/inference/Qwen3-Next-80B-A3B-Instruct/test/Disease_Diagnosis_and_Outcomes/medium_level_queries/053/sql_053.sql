WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

pneumonia_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id,
    CASE 
      WHEN LOWER(dic.long_title) LIKE '%aspiration%' THEN 'aspiration'
      WHEN LOWER(dic.long_title) LIKE '%community%' AND LOWER(dic.long_title) NOT LIKE '%aspiration%' THEN 'community_acquired'
      ELSE NULL
    END AS pneumonia_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code 
    AND di.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%pneumonia%'
    AND (LOWER(dic.long_title) LIKE '%aspiration%' OR LOWER(dic.long_title) LIKE '%community%')
),

first_icu_stay AS (
  SELECT 
    hadm_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

icu_day1 AS (
  SELECT 
    fis.hadm_id,
    CASE 
      WHEN fis.intime <= TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR) THEN 'Yes'
      ELSE 'No'
    END AS icu_day1
  FROM first_icu_stay fis
  INNER JOIN patient_admissions pa ON fis.hadm_id = pa.hadm_id
  WHERE fis.rn = 1
),

total_diagnoses_per_admission AS (
  SELECT 
    hadm_id,
    COUNT(*) AS total_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

pneumonia_diagnoses_count AS (
  SELECT 
    hadm_id,
    COUNT(*) AS pneumonia_diagnoses_count
  FROM pneumonia_diagnoses
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.los_days,
    pa.hospital_expire_flag,
    pd.pneumonia_type,
    icu.icu_day1,
    td.total_diagnoses,
    COALESCE(pdc.pneumonia_diagnoses_count, 0) AS pneumonia_diagnoses_count
  FROM patient_admissions pa
  INNER JOIN pneumonia_diagnoses pd ON pa.hadm_id = pd.hadm_id
  LEFT JOIN icu_day1 icu ON pa.hadm_id = icu.hadm_id
  INNER JOIN total_diagnoses_per_admission td ON pa.hadm_id = td.hadm_id
  LEFT JOIN pneumonia_diagnoses_count pdc ON pa.hadm_id = pdc.hadm_id
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN los_days >= 8 THEN '≥8 days'
    ELSE 'Unknown'
  END AS los_group,
  icu_day1,
  AVG(CASE WHEN pneumonia_type = 'aspiration' THEN hospital_expire_flag END) * 100 AS aspiration_mortality_pct,
  AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN hospital_expire_flag END) * 100 AS cap_mortality_pct,
  AVG(CASE WHEN pneumonia_type = 'aspiration' THEN total_diagnoses - pneumonia_diagnoses_count END) AS avg_comorbidities_aspiration,
  AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN total_diagnoses - pneumonia_diagnoses_count END) AS avg_comorbidities_cap,
  (AVG(CASE WHEN pneumonia_type = 'aspiration' THEN hospital_expire_flag END) * 100) - 
  (AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN hospital_expire_flag END) * 100) AS abs_diff_mortality_pct,
  CASE 
    WHEN AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN hospital_expire_flag END) > 0 
    THEN (AVG(CASE WHEN pneumonia_type = 'aspiration' THEN hospital_expire_flag END) * 100) / 
         (AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN hospital_expire_flag END) * 100)
    ELSE NULL 
  END AS rel_diff_mortality_ratio
FROM cohort
WHERE pneumonia_type IN ('aspiration', 'community_acquired')
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;