WITH
-- Identify patients with Pulmonary Embolism diagnosis
pe_diagnoses AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
),

-- Get patient demographics and filter for women aged 64-74
patient_demographics AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),

-- Filter for women aged 64-74 with PE
target_population AS (
  SELECT pd.*
  FROM patient_demographics pd
  INNER JOIN pe_diagnoses pe
    ON pd.hadm_id = pe.hadm_id
  WHERE pd.age_at_admission BETWEEN 64 AND 74
),

-- Calculate medication complexity (distinct meds in first 24 hours)
medication_complexity AS (
  SELECT
    tp.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM target_population tp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON tp.hadm_id = pr.hadm_id
    AND pr.starttime <= DATETIME_ADD(tp.admittime, INTERVAL 24 HOUR)
  GROUP BY tp.hadm_id
),

-- Calculate LOS for each admission
los_calculation AS (
  SELECT
    tp.hadm_id,
    tp.hospital_expire_flag,
    DATETIME_DIFF(tp.dischtime, tp.admittime, HOUR) / 24.0 AS los_days
  FROM target_population tp
),

-- Identify 30-day readmissions
all_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmissions AS (
  SELECT
    aa.hadm_id,
    CASE 
      WHEN aa.next_admittime <= DATETIME_ADD(aa.dischtime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM all_admissions aa
  WHERE aa.hadm_id IN (SELECT hadm_id FROM target_population)
),

-- Combine all data
combined_data AS (
  SELECT
    tp.hadm_id,
    COALESCE(mc.med_count, 0) AS med_count,
    lc.los_days,
    lc.hospital_expire_flag,
    COALESCE(r.readmitted_30d, 0) AS readmitted_30d
  FROM target_population tp
  LEFT JOIN medication_complexity mc ON tp.hadm_id = mc.hadm_id
  LEFT JOIN los_calculation lc ON tp.hadm_id = lc.hadm_id
  LEFT JOIN readmissions r ON tp.hadm_id = r.hadm_id
),

-- Assign tertiles based on medication count
tertile_assignment AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM combined_data
)

-- Aggregate results by tertile
SELECT
  tertile,
  COUNT(*) AS admissions,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmitted_30d) * 100 AS readmission_30d_pct
FROM tertile_assignment
GROUP BY tertile
ORDER BY tertile;