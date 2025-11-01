WITH chest_pain_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
    AND icd_version = 10
),
patients_of_interest AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
    AND di.icd_code IN (SELECT icd_code FROM chest_pain_codes)
  GROUP BY p.subject_id
),
hs_tnt_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%t%high%'
     OR LOWER(label) LIKE '%troponin%high%'
),
first_hs_tnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN hs_tnt_item h ON le.itemid = h.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  INNER JOIN patients_of_interest p ON a.subject_id = p.subject_id
  WHERE le.valuenum IS NOT NULL
),
initial_troponin AS (
  SELECT valuenum
  FROM first_hs_tnt
  WHERE rn = 1
),
categorized AS (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum <= 14 THEN 'Normal'
      WHEN valuenum BETWEEN 15 AND 29 THEN 'Borderline'
      WHEN valuenum >= 30 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS category
  FROM initial_troponin
),
summary_stats AS (
  SELECT
    category,
    COUNT(*) AS count_val,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3,
    AVG(valuenum) AS mean_val
  FROM categorized
  WHERE category != 'Unknown'
  GROUP BY category
)
SELECT
  category,
  count_val AS count,
  ROUND(count_val * 100.0 / SUM(count_val) OVER (), 2) AS percentage,
  ROUND(mean_val, 2) AS mean_hs_tnt,
  ROUND(median, 2) AS median_hs_tnt,
  CONCAT('[', ROUND(q1, 2), '-', ROUND(q3, 2), ']') AS iqr_hs_tnt
FROM summary_stats
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
    ELSE 4
  END;