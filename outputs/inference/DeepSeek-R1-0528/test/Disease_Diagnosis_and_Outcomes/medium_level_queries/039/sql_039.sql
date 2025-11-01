WITH exclusion_diagnoses AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (
      -- Shock codes
      (icd_version = 9 AND (icd_code LIKE '785.5%' OR icd_code LIKE '998.0%')) OR
      (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code LIKE 'T81.1%')) OR
      -- Respiratory failure codes
      (icd_version = 9 AND (icd_code LIKE '518.8%' OR icd_code = '799.1')) OR
      (icd_version = 10 AND (icd_code LIKE 'J96%' OR icd_code = 'R09.2'))
    )
    AND seq_num <= 5
),

ami_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '410%') OR 
        (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
    )
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM exclusion_diagnoses)
),

filtered_admissions AS (
  SELECT *
  FROM ami_admissions
  WHERE age_at_admission BETWEEN 66 AND 76
),

base AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'emergent'
      WHEN admission_type = 'ELECTIVE' THEN 'non-emergent'
      ELSE 'other'
    END AS admission_type_group,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8'
      ELSE '<1'
    END AS los_group,
    CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY) ELSE NULL END AS time_to_death_days
  FROM filtered_admissions
)

SELECT 
  los_group,
  admission_type_group,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent,
  APPROX_QUANTILES(time_to_death_days, 100 IGNORE NULLS)[SAFE_OFFSET(50)] AS median_time_to_death_days
FROM base
WHERE 
  admission_type_group IN ('emergent', 'non-emergent')
  AND los_group IN ('1-3', '4-7', '>=8')
GROUP BY los_group, admission_type_group
ORDER BY admission_type_group, los_group;