WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 87 AND 97
),

-- Filter admissions with suspected ACS using ICD diagnoses
acs_admissions AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%angina%'
     OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d.long_title) LIKE '%chest pain%'
     OR d.icd_code IN ('R07.9', 'I20.0', 'I21.9', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I22.1', 'I22.8', 'I22.9')
),

-- Get Troponin T lab events
troponin_observations AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),

-- First (index) Troponin T per admission
index_troponin AS (
  SELECT 
    tobs.hadm_id,
    tobs.valuenum AS index_tn_t
  FROM troponin_observations tobs
  WHERE tobs.rn = 1
),

-- Combine ACS admissions with index Troponin T
acs_with_tn AS (
  SELECT 
    aa.hadm_id,
    a.hospital_expire_flag,
    it.index_tn_t,
    CASE
      WHEN it.index_tn_t <= 14 THEN 'Normal/Minimal'
      WHEN it.index_tn_t BETWEEN 15 AND 59 THEN 'Borderline'
      WHEN it.index_tn_t >= 60 THEN 'Elevated'
      ELSE NULL
    END AS tn_category
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON aa.hadm_id = a.hadm_id
  INNER JOIN index_troponin it
    ON aa.hadm_id = it.hadm_id
  WHERE it.index_tn_t IS NOT NULL
),

-- Aggregate by category
summary AS (
  SELECT
    tn_category,
    COUNT(*) AS count_patients,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM acs_with_tn
  WHERE tn_category IS NOT NULL
  GROUP BY tn_category
),

totals AS (
  SELECT SUM(count_patients) AS total_count
  FROM summary
)

-- Final output: category, count, percentage, mortality rate
SELECT
  s.tn_category,
  s.count_patients,
  ROUND(s.count_patients * 100.0 / t.total_count, 2) AS percentage,
  ROUND(s.mortality_rate * 100, 2) AS mortality_rate_percent
FROM summary s
CROSS JOIN totals t
ORDER BY 
  CASE s.tn_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;