WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
),
stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
    OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
serotonergic_drugs AS (
  SELECT drug_name_upper
  FROM UNNEST([
    'SERTRALINE', 'FLUOXETINE', 'PAROXETINE', 'CITALOPRAM', 'ESCITALOPRAM', 
    'FLUVOXAMINE', 'VENLAFAXINE', 'DULOXETINE', 'MILNACIPRAN', 'LEVOMILNACIPRAN',
    'VILAZODONE', 'VORTIOXETINE'
  ]) AS drug_name_upper
),
med_count AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS serotonergic_drug_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN base_cohort b
    ON p.hadm_id = b.hadm_id
  WHERE 
    UPPER(p.drug) IN (SELECT drug_name_upper FROM serotonergic_drugs)
    AND p.starttime < b.admittime + INTERVAL '48' HOUR
  GROUP BY p.hadm_id
)
SELECT 
  b.hadm_id,
  CASE WHEN s.hadm_id IS NOT NULL THEN 'hemorrhagic_stroke' ELSE 'control' END AS group_label,
  b.age_at_admission,
  COALESCE(m.serotonergic_drug_count, 0) AS serotonergic_drug_count,
  DATETIME_DIFF(b.dischtime, b.admittime, HOUR) / 24.0 AS los_hospital_days,
  b.hospital_expire_flag
FROM base_cohort b
LEFT JOIN stroke_admissions s
  ON b.hadm_id = s.hadm_id
LEFT JOIN med_count m
  ON b.hadm_id = m.hadm_id;