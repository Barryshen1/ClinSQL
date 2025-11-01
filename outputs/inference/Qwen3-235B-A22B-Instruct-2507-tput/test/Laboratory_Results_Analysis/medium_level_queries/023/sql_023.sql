WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),
acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
),
trop_t_lab AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t'
),
first_troponin_t AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN trop_t_lab t ON le.itemid = t.itemid
  JOIN acs_admissions aa ON le.hadm_id = aa.hadm_id
  WHERE le.valuenum IS NOT NULL
),
troponin_category AS (
  SELECT
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.04 THEN 'normal'
      WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline'
      WHEN valuenum > 0.1 THEN 'elevated'
      ELSE NULL
    END AS category
  FROM first_troponin_t
  WHERE rn = 1
),
admission_stats AS (
  SELECT
    tc.category,
    COUNT(*) AS admission_count,
    AVG(IF(a.hospital_expire_flag = 1, 1, 0)) AS mortality_rate
  FROM troponin_category tc
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON tc.hadm_id = a.hadm_id
  WHERE tc.category IS NOT NULL
  GROUP BY tc.category
),
total_count AS (
  SELECT SUM(admission_count) AS total_admissions
  FROM admission_stats
)
SELECT
  category AS troponin_t_category,
  admission_count,
  ROUND(admission_count * 100.0 / total_admissions, 2) AS percent_of_admissions,
  ROUND(mortality_rate * 100, 2) AS in_hospital_mortality_rate_percent
FROM admission_stats
CROSS JOIN total_count
ORDER BY
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;