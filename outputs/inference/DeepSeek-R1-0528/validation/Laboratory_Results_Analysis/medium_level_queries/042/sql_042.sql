WITH chest_pain_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
), 
troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN chest_pain_codes cpc
        ON di.icd_code = cpc.icd_code
        AND di.icd_version = cpc.icd_version
    )
),
first_troponin_t AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    le.flag,
    ROW_NUMBER() OVER (
      PARTITION BY c.hadm_id 
      ORDER BY le.charttime
    ) AS troponin_priority
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND c.subject_id = le.subject_id
  INNER JOIN troponin_t_items tti
    ON le.itemid = tti.itemid
),
classified_troponin AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    CASE 
      WHEN flag IN ('Normal', 'Low') THEN 'normal'
      WHEN flag = 'Borderline' THEN 'borderline'
      WHEN flag IN ('High', 'Abnormal') THEN 'elevated'
      ELSE 'unclassified'
    END AS troponin_category
  FROM first_troponin_t
  WHERE troponin_priority = 1  -- Keep only the first troponin test
),
aggregated AS (
  SELECT 
    troponin_category,
    COUNT(*) AS count,
    SUM(hospital_expire_flag) AS in_hospital_deaths
  FROM classified_troponin
  WHERE troponin_category != 'unclassified'  -- Exclude unclassified results
  GROUP BY troponin_category
)
SELECT 
  troponin_category,
  count,
  ROUND(count * 100.0 / SUM(count) OVER (), 2) AS percentage,
  in_hospital_deaths,
  ROUND(in_hospital_deaths * 100.0 / count, 2) AS mortality_percentage
FROM aggregated
ORDER BY 
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;