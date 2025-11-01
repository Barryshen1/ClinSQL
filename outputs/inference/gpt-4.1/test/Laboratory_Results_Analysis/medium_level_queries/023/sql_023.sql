WITH acs_icd_codes AS (
  -- List ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL -- MI
  SELECT '411.1', 9 UNION ALL -- Unstable angina
  SELECT 'I21', 10 UNION ALL -- MI
  SELECT 'I22', 10 UNION ALL -- Subsequent MI
  SELECT 'I20.0', 10 -- Unstable angina
),
acs_admissions AS (
  -- Admissions with ACS diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN acs_icd_codes acs
    ON d.icd_version = acs.icd_version
   AND (
     d.icd_code = acs.icd_code
     OR d.icd_code LIKE acs.icd_code || '%'
   )
),
female_acs_admissions AS (
  -- Female, age 67-77, ACS admissions
  SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN acs_admissions acs
    ON a.subject_id = acs.subject_id
   AND a.hadm_id = acs.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),
troponin_t_items AS (
  -- Find itemid for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin_t AS (
  -- Get initial Troponin T value per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS initial_charttime
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN troponin_t_items tti
    ON l.itemid = tti.itemid
  JOIN female_acs_admissions fa
    ON l.subject_id = fa.subject_id
   AND l.hadm_id = fa.hadm_id
  WHERE l.valuenum IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),
troponin_t_values AS (
  -- Get initial Troponin T value per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_t_value
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN initial_troponin_t it
    ON l.subject_id = it.subject_id
   AND l.hadm_id = it.hadm_id
   AND l.charttime = it.initial_charttime
),
cohort AS (
  -- Cohort with Troponin T category
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.anchor_age,
    fa.gender,
    fa.hospital_expire_flag,
    ttv.troponin_t_value,
    CASE
      WHEN ttv.troponin_t_value <= 0.04 THEN 'Normal (≤0.04)'
      WHEN ttv.troponin_t_value > 0.04 AND ttv.troponin_t_value <= 0.1 THEN 'Borderline (>0.04–0.1)'
      WHEN ttv.troponin_t_value > 0.1 THEN 'Elevated (>0.1)'
      ELSE 'Unknown'
    END AS troponin_t_category
  FROM female_acs_admissions fa
  JOIN troponin_t_values ttv
    ON fa.subject_id = ttv.subject_id
   AND fa.hadm_id = ttv.hadm_id
)
SELECT
  troponin_t_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_percent
FROM cohort
WHERE troponin_t_category != 'Unknown'
GROUP BY troponin_t_category
ORDER BY
  CASE troponin_t_category
    WHEN 'Normal (≤0.04)' THEN 1
    WHEN 'Borderline (>0.04–0.1)' THEN 2
    WHEN 'Elevated (>0.1)' THEN 3
    ELSE 4
  END;