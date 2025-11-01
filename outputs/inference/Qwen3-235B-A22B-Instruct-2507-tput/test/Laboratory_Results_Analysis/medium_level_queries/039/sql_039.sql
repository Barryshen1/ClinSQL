WITH chest_pain_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
),
eligible_admissions AS (
  SELECT a.hadm_id, p.subject_id, p.gender,
         (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN chest_pain_codes cp ON di.icd_code = cp.icd_code AND di.icd_version = cp.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
),
hstnt_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%t%high%sensit%'
),
index_hstnt AS (
  SELECT le.hadm_id, le.valuenum,
         ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hstnt_item h ON le.itemid = h.itemid
  JOIN eligible_admissions e ON le.hadm_id = e.hadm_id
  WHERE le.valuenum IS NOT NULL
),
first_hstnt AS (
  SELECT hadm_id, valuenum AS index_hstnt
  FROM index_hstnt
  WHERE rn = 1
),
categorized AS (
  SELECT 
    index_hstnt,
    CASE
      WHEN index_hstnt <= 0.04 THEN 'Normal'
      WHEN index_hstnt > 0.04 AND index_hstnt <= 0.1 THEN 'Borderline'
      WHEN index_hstnt > 0.1 THEN 'Injury'
      ELSE 'Unknown'
    END AS category
  FROM first_hstnt
),
summary_stats AS (
  SELECT
    category,
    COUNT(*) AS count_patients,
    AVG(index_hstnt) AS mean_hstnt,
    PERCENTILE_CONT(index_hstnt, 0.25) OVER (PARTITION BY category) AS q1_hstnt,
    PERCENTILE_CONT(index_hstnt, 0.5) OVER (PARTITION BY category) AS median_hstnt,
    PERCENTILE_CONT(index_hstnt, 0.75) OVER (PARTITION BY category) AS q3_hstnt
  FROM categorized
  WHERE category != 'Unknown'
  GROUP BY category, index_hstnt
),
aggregated AS (
  SELECT
    category,
    COUNT(*) AS count_patients,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
    AVG(mean_hstnt) AS mean_hstnt,
    AVG(median_hstnt) AS median_hstnt,
    AVG(q1_hstnt) AS q1_hstnt,
    AVG(q3_hstnt) AS q3_hstnt
  FROM summary_stats
  GROUP BY category
)
SELECT
  category,
  count_patients,
  percentage,
  ROUND(mean_hstnt, 4) AS mean_hstnt,
  ROUND(median_hstnt, 4) AS median_hstnt,
  CONCAT(ROUND(q1_hstnt, 4), ' - ', ROUND(q3_hstnt, 4)) AS iqr_hstnt
FROM aggregated
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
    ELSE 4
  END;