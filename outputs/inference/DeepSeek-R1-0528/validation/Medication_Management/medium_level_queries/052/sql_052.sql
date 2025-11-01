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
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND a.hadm_id IN (
      SELECT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%Type 2 diabetes%'
    )
    AND a.hadm_id IN (
      SELECT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%heart failure%'
    )
),
medications AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    e.charttime,
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(e.medication), r'insulin') THEN 1 
      ELSE 0 
    END AS insulin_flag,
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(e.medication), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|repaglinide|nateglinide') THEN 1 
      ELSE 0 
    END AS oral_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
),
cohort_med_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN charttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 48 HOUR) 
          THEN insulin_flag ELSE 0 
        END) AS insulin_first_48h,
    MAX(CASE 
          WHEN charttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 48 HOUR) 
          THEN oral_flag ELSE 0 
        END) AS oral_first_48h,
    MAX(CASE 
          WHEN charttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime 
          THEN insulin_flag ELSE 0 
        END) AS insulin_final_24h,
    MAX(CASE 
          WHEN charttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime 
          THEN oral_flag ELSE 0 
        END) AS oral_final_24h
  FROM medications
  GROUP BY hadm_id
)
SELECT 
  time_window,
  ROUND(100.0 * SUM(insulin_flag) / COUNT(*), 2) AS insulin_percentage,
  ROUND(100.0 * SUM(oral_flag) / COUNT(*), 2) AS oral_percentage
FROM (
  SELECT 
    'First 48h' AS time_window,
    insulin_first_48h AS insulin_flag,
    oral_first_48h AS oral_flag
  FROM cohort_med_flags
  UNION ALL
  SELECT 
    'Final 24h' AS time_window,
    insulin_final_24h AS insulin_flag,
    oral_final_24h AS oral_flag
  FROM cohort_med_flags
) 
GROUP BY time_window;