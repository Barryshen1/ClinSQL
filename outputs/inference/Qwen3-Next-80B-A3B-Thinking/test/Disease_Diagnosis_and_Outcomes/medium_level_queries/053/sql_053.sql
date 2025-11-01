WITH patient_data AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    CASE
      WHEN MAX(CASE WHEN d.long_title LIKE '%aspiration pneumonia%' THEN 1 ELSE 0 END) = 1 THEN 'aspiration'
      WHEN MAX(CASE WHEN d.long_title LIKE '%community-acquired pneumonia%' THEN 1 ELSE 0 END) = 1 THEN 'community-acquired'
      ELSE NULL
    END AS pneumonia_type,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNT(CASE WHEN d.long_title NOT LIKE '%aspiration pneumonia%' AND d.long_title NOT LIKE '%community-acquired pneumonia%' THEN 1 END) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
    AND i.intime <= a.admittime + INTERVAL 24 HOUR
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
  GROUP BY p.subject_id, a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime, i.stay_id
  HAVING pneumonia_type IS NOT NULL
)
SELECT
  los_category,
  icu_status,
  AVG(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) AS aspiration_mortality,
  AVG(CASE WHEN pneumonia_type = 'community-acquired' THEN mortality_rate END) AS community_mortality,
  AVG(CASE WHEN pneumonia_type = 'aspiration' THEN comorbidity_count END) AS aspiration_comorbidity,
  AVG(CASE WHEN pneumonia_type = 'community-acquired' THEN comorbidity_count END) AS community_comorbidity,
  (AVG(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) - AVG(CASE WHEN pneumonia_type = 'community-acquired' THEN mortality_rate END)) AS abs_diff,
  (AVG(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) - AVG(CASE WHEN pneumonia_type = 'community-acquired' THEN mortality_rate END)) / NULLIF(AVG(CASE WHEN pneumonia_type = 'community-acquired' THEN mortality_rate END), 0) AS rel_diff
FROM (
  SELECT
    los_category,
    icu_status,
    pneumonia_type,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(comorbidity_count) AS comorbidity_count
  FROM (
    SELECT
      *,
      CASE
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
        WHEN los_days >= 8 THEN '>=8'
        ELSE NULL
      END AS los_category
    FROM patient_data
  )
  GROUP BY los_category, icu_status, pneumonia_type
) sub
GROUP BY los_category, icu_status;