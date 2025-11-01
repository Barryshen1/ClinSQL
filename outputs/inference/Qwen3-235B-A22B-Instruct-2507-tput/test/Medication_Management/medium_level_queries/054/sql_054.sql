WITH patient_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 56 AND 66
),

diabetes_hf AS (
  SELECT
    pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY pa.hadm_id
  HAVING 
    -- Check for at least one diabetes diagnosis
    COUNT(CASE 
      WHEN LOWER(d.long_title) LIKE '%diabetes%' 
        OR d.icd_code LIKE 'E08%' 
        OR d.icd_code LIKE 'E09%' 
        OR d.icd_code LIKE 'E10%' 
        OR d.icd_code LIKE 'E11%' 
        OR d.icd_code LIKE 'E13%' 
      THEN 1 END) >= 1
    AND 
    -- Check for at least one heart failure diagnosis
    COUNT(CASE 
      WHEN LOWER(d.long_title) LIKE '%heart failure%' 
        OR d.icd_code LIKE 'I50%' 
      THEN 1 END) >= 1
),

gla1_meds AS (
  SELECT DISTINCT
    LOWER(drug) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%tirzepatide%'
     OR LOWER(drug) LIKE '%glp-1%'
     OR LOWER(drug) LIKE '%glucagon-like peptide-1%'
),

usage_flags AS (
  SELECT
    pa.subject_id,
    MAX(CASE
      WHEN pr.starttime <= pa.admittime + INTERVAL '48' HOUR
        AND (pr.stoptime IS NULL OR pr.stoptime >= pa.admittime)
      THEN 1 ELSE 0 END) AS used_first_48h,
    MAX(CASE
      WHEN pr.starttime <= pa.dischtime
        AND (pr.stoptime IS NULL OR pr.stoptime >= pa.dischtime - INTERVAL '24' HOUR)
        AND pa.dischtime - INTERVAL '24' HOUR <= COALESCE(pr.stoptime, pa.dischtime)
      THEN 1 ELSE 0 END) AS used_last_24h
  FROM patient_admissions pa
  INNER JOIN diabetes_hf dh
    ON pa.hadm_id = dh.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
  LEFT JOIN gla1_meds g
    ON LOWER(pr.drug) = g.drug_lower
  GROUP BY pa.subject_id
),

summary AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(used_first_48h) AS used_first_48h_count,
    SUM(used_last_24h) AS used_last_24h_count,
    ROUND(100.0 * SUM(used_first_48h) / COUNT(*), 2) AS pct_first_48h,
    ROUND(100.0 * SUM(used_last_24h) / COUNT(*), 2) AS pct_last_24h,
    ROUND(100.0 * SUM(used_last_24h) / COUNT(*) - 100.0 * SUM(used_first_48h) / COUNT(*), 2) AS net_change_pct
  FROM usage_flags
)

SELECT
  pct_first_48h,
  pct_last_24h,
  net_change_pct
FROM summary;