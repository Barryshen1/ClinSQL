WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
pneumonia_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.age_at_admission
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE 
    c.age_at_admission BETWEEN 76 AND 86
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '486%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J12%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J13%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J14%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J15%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J16%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J17%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J18%')
    )
),
medication_complexity AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS drug_count
  FROM pneumonia_admissions p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN p.admittime AND DATETIME_ADD(p.admittime, INTERVAL 7 DAY)
  GROUP BY p.hadm_id
),
admissions_with_next AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Get next admission time for the same patient
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
readmission_flags AS (
  SELECT 
    p.hadm_id,
    p.hospital_expire_flag,
    -- Readmission flag: 1 if discharged alive and next admission within 30 days
    CASE 
      WHEN p.hospital_expire_flag = 1 THEN 0
      WHEN a.next_admittime > p.dischtime 
        AND a.next_admittime <= DATETIME_ADD(p.dischtime, INTERVAL 30 DAY) 
        THEN 1 
      ELSE 0 
    END AS readmission_flag
  FROM pneumonia_admissions p
  LEFT JOIN admissions_with_next a
    ON p.hadm_id = a.hadm_id
),
base AS (
  SELECT 
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    COALESCE(m.drug_count, 0) AS drug_count,  -- Handle no medications
    r.readmission_flag,
    DATETIME_DIFF(p.dischtime, p.admittime, DAY) AS los_days
  FROM pneumonia_admissions p
  LEFT JOIN medication_complexity m ON p.hadm_id = m.hadm_id
  LEFT JOIN readmission_flags r ON p.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY drug_count) AS tertile
  FROM base
)
SELECT 
  tertile,
  COUNT(*) AS admissions_count,
  MIN(drug_count) AS min_drug_count,
  ROUND(AVG(drug_count), 2) AS avg_drug_count,
  MAX(drug_count) AS max_drug_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(readmission_flag) * 100, 2) AS readmission_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;