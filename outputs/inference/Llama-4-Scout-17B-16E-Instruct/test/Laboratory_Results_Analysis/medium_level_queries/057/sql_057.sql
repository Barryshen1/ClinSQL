WITH 
  -- Define troponin T categories
  troponin_categories AS (
    SELECT 
      le.hadm_id,
      CASE 
        WHEN le.valuenum <= 0.04 THEN 'normal'
        WHEN le.valuenum > 0.04 AND le.valuenum <= 0.1 THEN 'borderline'
        WHEN le.valuenum > 0.1 THEN 'elevated'
        ELSE 'unknown'
      END AS troponin_category
    FROM (
      SELECT 
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
      FROM 
        `physionet-data.mimiciv_3_1_hosp.labevents`
      WHERE 
        itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Troponin T%')
    ) le
    WHERE 
      le.rn = 1
  ),
  -- Filter patients and admissions
  target_patients AS (
    SELECT 
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admission_type,
      a.discharge_location
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 79 AND 89
      AND a.admission_type IN ('Emergency', 'Urgent')
  ),
  -- Identify ACS admissions
  acs_admissions AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '%410%'
  )

-- Final query
SELECT 
  tc.troponin_category,
  COUNT(DISTINCT tc.hadm_id) AS admission_count
FROM 
  troponin_categories tc
JOIN 
  target_patients tp ON tc.hadm_id = tp.hadm_id
JOIN 
  acs_admissions aa ON tc.hadm_id = aa.hadm_id
GROUP BY 
  tc.troponin_category;