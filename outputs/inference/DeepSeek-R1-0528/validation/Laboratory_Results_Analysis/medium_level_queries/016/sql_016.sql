WITH acs_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code IN ('4111', '41181')))
          OR
          (di.icd_version = 10 AND (di.icd_code = 'I200' OR 
                                    di.icd_code LIKE 'I21%' OR 
                                    di.icd_code LIKE 'I22%' OR 
                                    di.icd_code LIKE 'I23%' OR 
                                    di.icd_code LIKE 'I24%'))
        )
    )
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 79 AND 89
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    l.ref_range_upper,
    l.itemid
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON aa.hadm_id = l.hadm_id
  WHERE 
    l.itemid IN (51003, 50911)   -- Troponin T and high-sensitivity Troponin T
    AND l.valuenum IS NOT NULL   -- Ensure numeric value exists
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),
troponin_categorized AS (
  SELECT 
    hadm_id,
    troponin_value,
    -- Determine reference upper limit (use default if missing)
    CASE 
      WHEN ref_range_upper IS NOT NULL THEN ref_range_upper
      WHEN itemid = 51003 THEN 0.1   -- Default for Troponin T
      WHEN itemid = 50911 THEN 14    -- Default for high-sensitivity Troponin T
    END AS ref_upper,
    -- Categorize based on value vs. ref_upper
    CASE 
      WHEN troponin_value <= (CASE 
                                WHEN ref_range_upper IS NOT NULL THEN ref_range_upper
                                WHEN itemid = 51003 THEN 0.1
                                WHEN itemid = 50911 THEN 14
                              END) 
        THEN 'normal'
      WHEN troponin_value <= 3 * (CASE 
                                    WHEN ref_range_upper IS NOT NULL THEN ref_range_upper
                                    WHEN itemid = 51003 THEN 0.1
                                    WHEN itemid = 50911 THEN 14
                                  END) 
        THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM first_troponin
),
aggregated AS (
  SELECT 
    category,
    COUNT(*) AS count,
    AVG(troponin_value) AS mean,
    APPROX_QUANTILES(troponin_value, 100) AS quantiles
  FROM troponin_categorized
  GROUP BY category
)
SELECT 
  category,
  count,
  ROUND(count * 100.0 / SUM(count) OVER (), 2) AS percentage,
  mean,
  quantiles[OFFSET(25)] AS q1,
  quantiles[OFFSET(50)] AS median,
  quantiles[OFFSET(75)] AS q3
FROM aggregated
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;