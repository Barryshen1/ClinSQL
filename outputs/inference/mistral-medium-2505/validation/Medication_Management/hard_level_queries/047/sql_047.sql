WITH
-- Define serotonergic drugs (example list - expand as needed)
serotonergic_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%fluoxetine%'
     OR LOWER(drug) LIKE '%sertraline%'
     OR LOWER(drug) LIKE '%paroxetine%'
     OR LOWER(drug) LIKE '%citalopram%'
     OR LOWER(drug) LIKE '%escitalopram%'
     OR LOWER(drug) LIKE '%venlafaxine%'
     OR LOWER(drug) LIKE '%duloxetine%'
     OR LOWER(drug) LIKE '%trazodone%'
),

-- Female inpatients aged 48-58
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- Hemorrhagic stroke cases (ICD-10: I61.x)
stroke_cases AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.los_hours,
    f.hospital_expire_flag,
    'Stroke' AS cohort
  FROM female_patients f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
  WHERE d.icd_code LIKE 'I61%'
    AND d.icd_version = 10
),

-- Age-matched controls (non-stroke)
controls AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.los_hours,
    f.hospital_expire_flag,
    'Control' AS cohort
  FROM female_patients f
  WHERE f.subject_id NOT IN (SELECT subject_id FROM stroke_cases)
),

-- Combined cohort
cohort AS (
  SELECT * FROM stroke_cases
  UNION ALL
  SELECT * FROM controls
),

-- First 48-hour medications
first_48h_meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.cohort,
    p.drug,
    p.starttime,
    TIMESTAMP_DIFF(p.starttime, a.admittime, HOUR) AS hours_since_admission
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(p.starttime, a.admittime, HOUR) BETWEEN 0 AND 48
),

-- Serotonergic drug counts
serotonergic_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.cohort,
    COUNT(DISTINCT s.drug) AS serotonergic_drug_count
  FROM first_48h_meds f
  JOIN serotonergic_drugs s
    ON LOWER(f.drug) = LOWER(s.drug)
  GROUP BY f.subject_id, f.hadm_id, f.cohort
),

-- Medication complexity (simplified as unique drug count)
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    cohort,
    COUNT(DISTINCT f.drug) AS unique_drug_count,
    COUNT(DISTINCT CASE WHEN LOWER(f.drug) LIKE '%sertraline%' THEN f.drug END) AS sertraline_count,
    COUNT(DISTINCT CASE WHEN LOWER(f.drug) LIKE '%fluoxetine%' THEN f.drug END) AS fluoxetine_count,
    -- Using unique drug count as complexity score
    COUNT(DISTINCT f.drug) AS complexity_score
  FROM first_48h_meds f
  GROUP BY subject_id, hadm_id, cohort
),

-- Quartile analysis
complexity_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    cohort,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM med_complexity
)

-- Final analysis
SELECT
  c.cohort,
  s.serotonergic_drug_count,
  CASE WHEN s.serotonergic_drug_count >= 2 THEN '≥2 serotonergic drugs' ELSE '<2 serotonergic drugs' END AS serotonergic_group,
  q.complexity_quartile,
  AVG(c.los_hours) AS avg_los_hours,
  AVG(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  COUNT(*) AS patient_count
FROM cohort c
LEFT JOIN serotonergic_counts s
  ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id
LEFT JOIN complexity_quartiles q
  ON c.subject_id = q.subject_id AND c.hadm_id = q.hadm_id
GROUP BY
  c.cohort,
  s.serotonergic_drug_count,
  serotonergic_group,
  q.complexity_quartile
ORDER BY
  c.cohort,
  s.serotonergic_drug_count DESC,
  q.complexity_quartile;