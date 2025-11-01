WITH heart_failure_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(d_diag.long_title) LIKE '%acute%decompensated%heart%failure%'
),

day1_icu AS (
  SELECT DISTINCT
    a.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS day1_icu
  FROM heart_failure_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
    AND i.intime >= a.admittime
    AND i.intime < DATETIME_ADD(a.admittime, INTERVAL '24' HOUR)
),

ckd_diabetes AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(d_diag.long_title) LIKE '%chronic%kidney%disease%' 
              OR d.icd_code IN ('N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') 
              THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN LOWER(d_diag.long_title) LIKE '%diabetes%' 
              OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' 
              THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
  GROUP BY d.hadm_id
)

SELECT
  CASE WHEN h.los <= 7 THEN '≤7' ELSE '>7' END AS los_group,
  d.day1_icu,
  ROUND(AVG(h.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(c.ckd_flag) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(c.diabetes_flag) * 100, 2) AS diabetes_prevalence_pct
FROM heart_failure_admissions h
JOIN day1_icu d ON h.hadm_id = d.hadm_id
LEFT JOIN ckd_diabetes c ON h.hadm_id = c.hadm_id
GROUP BY CASE WHEN h.los <= 7 THEN '≤7' ELSE '>7' END, d.day1_icu;