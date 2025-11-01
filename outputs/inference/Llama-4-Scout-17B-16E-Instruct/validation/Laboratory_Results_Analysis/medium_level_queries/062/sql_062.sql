WITH 
-- Identify ACS admissions for females aged 46-56
acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE 'I24%'  -- ACS ICD code
    )
),

-- Categorize hs-TnT levels
hs_tnt_levels AS (
  SELECT 
    hadm_id,
    charttime,
    value,
    valuenum,
    CASE
      WHEN valuenum < 6 THEN 'Normal'
      WHEN valuenum BETWEEN 6 AND 14 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS hs_tnt_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 43121  -- hs-TnT itemid
)

-- Combine admissions with hs-TnT levels and calculate length of stay
SELECT 
  ht.hs_tnt_category,
  COUNT(DISTINCT aa.hadm_id) AS count_admissions,
  COUNT(DISTINCT aa.hadm_id) / SUM(COUNT(DISTINCT aa.hadm_id)) OVER () AS percentage_admissions,
  AVG(DATE_DIFF(aa.dischtime, aa.admittime, 'DAY')) AS mean_length_of_stay
FROM 
  acs_admissions aa
JOIN 
  hs_tnt_levels ht
ON 
  aa.hadm_id = ht.hadm_id
WHERE 
  aa.dischtime IS NOT NULL AND aa.admittime IS NOT NULL
GROUP BY 
  ht.hs_tnt_category
ORDER BY 
  ht.hs_tnt_category;