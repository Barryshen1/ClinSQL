WITH
-- Define DKA ICD-10 codes (truncated for brevity; use full list in practice)
dka_codes AS (
  SELECT * FROM UNNEST([
    'E10.10', 'E10.11', 'E10.12', 'E10.13', 'E10.14', 'E10.15', 'E10.16', 'E10.19',
    'E11.10', 'E11.11', 'E11.12', 'E11.13', 'E11.14', 'E11.15', 'E11.16', 'E11.19'
  ]) AS icd_code
),
-- Define hyperkalemia-risk drug names
hyperkalemia_drugs AS (
  SELECT * FROM UNNEST([
    'Lisinopril', 'Enalapril', 'Ramipril', 'Quinapril', 'Perindopril', 'Fosinopril', 'Captopril', 'Benazepril',
    'Losartan', 'Valsartan', 'Irbesartan', 'Candesartan', 'Telmisartan', 'Olmesartan', 'Eprosartan',
    'Spironolactone', 'Amiloride', 'Triamterene', 'Eplerenone',
    'Ibuprofen', 'Naproxen', 'Diclofenac', 'Indomethacin', 'Celecoxib',
    'Heparin', 'Trimethoprim', 'Cyclosporine', 'Tacrolimus', 'Cisplatin'
  ]) AS drug_name
),
-- Eligible admissions: female, age 84-94, with DKA diagnosis
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN dka_codes dc ON d.icd_code = dc.icd_code
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
    )
),
-- Prescriptions during admission (filtered by time)
admission_prescriptions AS (
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_admissions e ON p.hadm_id = e.hadm_id
  WHERE p.starttime BETWEEN e.admittime AND e.dischtime
    AND p.drug IS NOT NULL
),
-- Medication complexity (distinct drugs per admission)
admission_complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS med_complexity
  FROM admission_prescriptions
  GROUP BY hadm_id
),
-- Hyperkalemia-risk drug interactions (≥2 distinct drugs per admission)
hyperkalemia_interactions AS (
  SELECT
    ap.hadm_id,
    COUNT(DISTINCT CASE WHEN hd.drug_name IS NOT NULL THEN ap.drug END) AS hyperkalemia_drug_count
  FROM admission_prescriptions ap
  LEFT JOIN hyperkalemia_drugs hd ON ap.drug = hd.drug_name
  GROUP BY ap.hadm_id
  HAVING hyperkalemia_drug_count >= 2
),
-- Cohort with outcomes and exposure status
cohort AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.age_at_admission,
    e.hospital_expire_flag,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los,
    COALESCE(ac.med_complexity, 0) AS med_complexity,
    CASE WHEN hi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hyperkalemia_interaction
  FROM eligible_admissions e
  LEFT JOIN admission_complexity ac ON e.hadm_id = ac.hadm_id
  LEFT JOIN hyperkalemia_interactions hi ON e.hadm_id = hi.hadm_id
),
-- Add complexity percentiles and quartiles
cohort_with_percentile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS complexity_percentile,
    NTILE(4) OVER (ORDER BY med_complexity) AS complexity_quartile
  FROM cohort
)
-- Compare exposed vs. unexposed groups
SELECT
  has_hyperkalemia_interaction,
  AVG(med_complexity) AS mean_med_complexity,
  AVG(complexity_percentile) AS mean_complexity_percentile,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality
FROM cohort_with_percentile
GROUP BY has_hyperkalemia_interaction

UNION ALL

-- Top complexity quartile (quartile 4)
SELECT
  NULL AS has_hyperkalemia_interaction,
  NULL AS mean_med_complexity,
  NULL AS mean_complexity_percentile,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality
FROM cohort_with_percentile
WHERE complexity_quartile = 4;