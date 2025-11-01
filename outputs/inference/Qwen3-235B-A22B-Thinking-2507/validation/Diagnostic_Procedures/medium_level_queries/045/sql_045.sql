WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL  -- Ensure valid LOS calculation
),
dvt_admissions AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admission
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id
  WHERE 
    -- ICD-9 codes for DVT
    (d.icd_version = 9 AND d.icd_code IN ('45111','45119','4512','45181','45183','45184','45189','4519','4530','4531','4532','4533','4534','4535','4536','4537','4538','4539'))
    OR 
    -- ICD-10 codes for DVT
    (d.icd_version = 10 AND (d.icd_code LIKE 'I80.%' OR d.icd_code LIKE 'I82.%'))
),
admission_details AS (
  SELECT 
    dvt.*,
    -- Calculate LOS in days (adding 1 because same-day admission/discharge = 1 day)
    DATE_DIFF(CAST(dvt.dischtime AS DATE), CAST(dvt.admittime AS DATE), DAY) + 1 AS los_days,
    -- Determine if admission included ICU stay
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status
  FROM dvt_admissions dvt
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON dvt.hadm_id = i.hadm_id
),
lab_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  icu_status,
  COUNT(*) AS admission_count,
  AVG(COALESCE(lc.lab_count, 0)) AS mean_lab_count
FROM admission_details ad
LEFT JOIN lab_counts lc
  ON ad.hadm_id = lc.hadm_id
WHERE los_days BETWEEN 1 AND 8
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;