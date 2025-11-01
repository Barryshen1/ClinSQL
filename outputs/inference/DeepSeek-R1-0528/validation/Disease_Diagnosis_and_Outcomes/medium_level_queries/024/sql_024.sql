WITH sepsis_cohort AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit,
    -- Calculate LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Check ICU in first 24h
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
      WHERE 
        icu.hadm_id = adm.hadm_id AND
        icu.intime < DATETIME_ADD(adm.admittime, INTERVAL 1 DAY) AND
        icu.outtime > adm.admittime
    ) AS in_icu_day1,
    -- CKD flag
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = adm.hadm_id AND
        (
          (d.icd_version = 9 AND d.icd_code IN ('5851','5852','5853','5854','5855','5856','5859')) OR
          (d.icd_version = 10 AND d.icd_code IN ('N181','N182','N183','N184','N185','N186','N189'))
        )
    ) AS ckd_flag,
    -- Diabetes flag
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = adm.hadm_id AND
        (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
          (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('E08','E09','E10','E11','E13'))
        )
    ) AS diabetes_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
      ON p.subject_id = adm.subject_id
  WHERE 
    p.gender = 'F' AND
    -- Sepsis without septic shock
    adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code IN ('99591','99592')) OR
        (icd_version = 10 AND icd_code IN ('A419','A4189','R6520'))
    ) AND
    adm.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code = '78552') OR
        (icd_version = 10 AND icd_code IN ('R6521','T8112'))
    )
)
SELECT
  CASE 
    WHEN los_days <= 5 AND in_icu_day1 THEN 'LOS≤5 and ICU day1'
    WHEN los_days <= 5 AND NOT in_icu_day1 THEN 'LOS≤5 and non-ICU day1'
    WHEN los_days > 5 AND in_icu_day1 THEN 'LOS>5 and ICU day1'
    WHEN los_days > 5 AND NOT in_icu_day1 THEN 'LOS>5 and non-ICU day1'
  END AS group_name,
  COUNT(hadm_id) AS N,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(hadm_id), 2) AS mortality_percent,
  ROUND(100.0 * SUM(CAST(ckd_flag AS INT)) / COUNT(hadm_id), 2) AS ckd_prevalence,
  ROUND(100.0 * SUM(CAST(diabetes_flag AS INT)) / COUNT(hadm_id), 2) AS diabetes_prevalence
FROM sepsis_cohort
WHERE 
  age_at_admit BETWEEN 49 AND 59
GROUP BY group_name
ORDER BY group_name;