WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    -- T2DM (ICD-9: 250.x0/x2; ICD-10: E11.x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250%' AND (SUBSTR(di.icd_code, -1) = '0' OR SUBSTR(di.icd_code, -1) = '2'))
          OR 
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
        )
    )
    -- Heart Failure (ICD-9: 428.x, 402.x1, 404.x1/x3; ICD-10: I50.x, I11.0, I13.0/x2)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND (
            di.icd_code LIKE '428%' 
            OR di.icd_code IN ('402.01','402.11','402.91','404.01','404.03','404.11','404.13','404.91','404.93')
          )) 
          OR 
          (di.icd_version = 10 AND (
            di.icd_code LIKE 'I50%' 
            OR di.icd_code IN ('I11.0','I13.0','I13.2')
          ))
        )
    )
),

glp1_events AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
          WHEN e.scheduletime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
          THEN 1 
          ELSE 0 
        END) AS in_first_24h,
    MAX(CASE 
          WHEN e.scheduletime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime 
          THEN 1 
          ELSE 0 
        END) AS in_final_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id  -- Added subject_id join
    AND c.hadm_id = e.hadm_id
    AND e.event_txt = 'Given'
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
    AND e.subject_id = ed.subject_id
    AND (
      CONTAINS_SUBSTR(ed.product_description, 'exenatide') OR  -- Replaced ILIKE
      CONTAINS_SUBSTR(ed.product_description, 'liraglutide') OR
      CONTAINS_SUBSTR(ed.product_description, 'dulaglutide') OR
      CONTAINS_SUBSTR(ed.product_description, 'semaglutide') OR
      CONTAINS_SUBSTR(ed.product_description, 'lixisenatide')
    )
    AND UPPER(ed.route) IN ('IV', 'SUBCUTANEOUS', 'SUBCUT', 'INJECTION')  -- Case-insensitive route
  GROUP BY c.hadm_id
)

SELECT 
  COUNT(hadm_id) AS total_patients,
  SUM(COALESCE(in_first_24h, 0)) AS count_first_24h,
  SUM(COALESCE(in_final_48h, 0)) AS count_final_48h,
  ROUND(SUM(COALESCE(in_first_24h, 0)) * 100.0 / COUNT(hadm_id), 2) AS prevalence_first_24h,
  ROUND(SUM(COALESCE(in_final_48h, 0)) * 100.0 / COUNT(hadm_id), 2) AS prevalence_final_48h,
  ROUND(
    (SUM(COALESCE(in_final_48h, 0)) * 100.0 / COUNT(hadm_id)) - 
    (SUM(COALESCE(in_first_24h, 0)) * 100.0 / COUNT(hadm_id)), 
    2
  ) AS absolute_change,
  ROUND(
    (
      (SUM(COALESCE(in_final_48h, 0)) * 100.0 / COUNT(hadm_id)) - 
      (SUM(COALESCE(in_first_24h, 0)) * 100.0 / COUNT(hadm_id))
    ) / 
    NULLIF(SUM(COALESCE(in_first_24h, 0)) * 100.0 / COUNT(hadm_id), 0) * 100, 
    2
  ) AS relative_change
FROM glp1_events;