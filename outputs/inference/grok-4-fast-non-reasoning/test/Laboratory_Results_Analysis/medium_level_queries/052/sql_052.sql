WITH cohort AS (
  -- Filter male patients aged 76-86 with primary AMI admission (ICD-10)
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
),

first_troponin AS (
  -- Get first Troponin I measurement per admission
  SELECT 
    c.subject_id,
    c.hadm_id,
    l.charttime,
    l.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponini%'
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime ASC) = 1
),

categorized AS (
  -- Categorize Troponin values
  SELECT 
    CASE 
      WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
      WHEN valuenum BETWEEN 0.04 AND 0.40 THEN 'Borderline (0.04–0.40)'
      WHEN valuenum >= 0.40 THEN 'Elevated (≥0.40)'
    END AS troponin_category,
    valuenum
  FROM first_troponin
  WHERE valuenum IS NOT NULL
)

-- Distribution: counts, percentages; overall stats
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS percentage,
  NULL AS mean,
  NULL AS median,
  NULL AS iqr
FROM categorized
GROUP BY troponin_category

UNION ALL

-- Overall row for mean, median, IQR (no category)
SELECT 
  'Overall' AS troponin_category,
  COUNT(*) AS count,
  100.0 AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  PERCENTILE_CONT(valuenum, 0.5) OVER() AS median,
  PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr
FROM categorized

ORDER BY 
  CASE troponin_category 
    WHEN 'Normal (≤0.04)' THEN 1 
    WHEN 'Borderline (0.04–0.40)' THEN 2 
    WHEN 'Elevated (≥0.40)' THEN 3 
    WHEN 'Overall' THEN 4 
  END;