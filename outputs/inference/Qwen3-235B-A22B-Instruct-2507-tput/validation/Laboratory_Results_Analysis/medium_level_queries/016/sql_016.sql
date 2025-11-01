WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
),
acs_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%unstable angina%'
),
acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN acs_icd_codes acs
    ON di.icd_code = acs.icd_code AND di.icd_version = 10
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
),
troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t'
),
first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum AS troponin_t_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN troponin_t_items tti ON le.itemid = tti.itemid
  INNER JOIN acs_admissions aa ON le.hadm_id = aa.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp`.admissions a WHERE a.hadm_id = le.hadm_id)
),
first_troponin_first_only AS (
  SELECT hadm_id, troponin_t_value
  FROM first_troponin
  WHERE rn = 1
),
troponin_categorized AS (
  SELECT
    hadm_id,
    troponin_t_value,
    CASE
      WHEN troponin_t_value < 0.014 THEN 'normal'
      WHEN troponin_t_value < 0.030 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM first_troponin_first_only
),
summary_stats AS (
  SELECT
    category,
    COUNT(*) AS count_patients,
    AVG(troponin_t_value) AS mean_troponin,
    APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(50)] AS median_troponin,
    APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(25)] AS q1_troponin,
    APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(75)] AS q3_troponin
  FROM troponin_categorized
  GROUP BY category
),
total_count AS (
  SELECT SUM(count_patients) AS total FROM summary_stats
)
SELECT
  ss.category,
  ss.count_patients,
  ROUND(100.0 * ss.count_patients / tc.total, 2) AS percentage,
  ROUND(ss.mean_troponin, 4) AS mean_troponin,
  ss.median_troponin,
  CONCAT('[', ss.q1_troponin, ', ', ss.q3_troponin, ']') AS iqr_troponin
FROM summary_stats ss
CROSS JOIN total_count tc
ORDER BY FIELD(ss.category, 'normal', 'borderline', 'elevated');