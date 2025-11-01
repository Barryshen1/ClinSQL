WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250%') OR
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
      WHERE hf.subject_id = a.subject_id 
        AND hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 9 AND hf.icd_code LIKE '428%') OR
          (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%')
        )
    )
),
insulin_administrations AS (
  SELECT 
    e.subject_id, 
    e.hadm_id, 
    e.charttime,
    CASE 
      WHEN LOWER(ed.product_description) LIKE '%glargine%' 
        OR LOWER(ed.product_description) LIKE '%detemir%' 
        OR LOWER(ed.product_description) LIKE '%nph%' 
        OR LOWER(ed.product_description) LIKE '%isophane%' 
        OR LOWER(ed.product_description) LIKE '%degludec%' 
        THEN 'basal'
      WHEN LOWER(ed.product_description) LIKE '%lispro%' 
        OR LOWER(ed.product_description) LIKE '%aspart%' 
        OR LOWER(ed.product_description) LIKE '%glulisine%' 
        THEN 'bolus'
      WHEN LOWER(ed.product_description) LIKE '%regular%' 
        OR LOWER(ed.product_description) LIKE '%human insulin%' 
        THEN 'sliding'
      ELSE NULL 
    END AS ins_type
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  WHERE LOWER(ed.product_description) LIKE '%insulin%' 
    AND ed.product_description IS NOT NULL
),
insulin_mins AS (
  SELECT 
    c.hadm_id, 
    c.admittime, 
    c.dischtime,
    MIN(CASE WHEN ia.ins_type = 'basal' THEN ia.charttime END) AS min_basal,
    MIN(CASE WHEN ia.ins_type = 'bolus' THEN ia.charttime END) AS min_bolus,
    MIN(CASE WHEN ia.ins_type = 'sliding' THEN ia.charttime END) AS min_sliding
  FROM cohort c
  LEFT JOIN insulin_administrations ia 
    ON c.subject_id = ia.subject_id 
    AND c.hadm_id = ia.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
),
counts AS (
  SELECT 
    'basal' AS regimen,
    COUNT(*) AS total,
    SUM(CASE 
      WHEN min_basal IS NOT NULL 
        AND min_basal >= admittime 
        AND min_basal < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) 
      THEN 1 ELSE 0 
    END) AS num_first72,
    SUM(CASE 
      WHEN min_basal IS NOT NULL 
        AND min_basal >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
        AND min_basal < dischtime 
      THEN 1 ELSE 0 
    END) AS num_final48
  FROM insulin_mins
  UNION ALL
  SELECT 
    'bolus' AS regimen,
    COUNT(*) AS total,
    SUM(CASE 
      WHEN min_bolus IS NOT NULL 
        AND min_bolus >= admittime 
        AND min_bolus < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) 
      THEN 1 ELSE 0 
    END) AS num_first72,
    SUM(CASE 
      WHEN min_bolus IS NOT NULL 
        AND min_bolus >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
        AND min_bolus < dischtime 
      THEN 1 ELSE 0 
    END) AS num_final48
  FROM insulin_mins
  UNION ALL
  SELECT 
    'sliding-scale' AS regimen,
    COUNT(*) AS total,
    SUM(CASE 
      WHEN min_sliding IS NOT NULL 
        AND min_sliding >= admittime 
        AND min_sliding < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) 
      THEN 1 ELSE 0 
    END) AS num_first72,
    SUM(CASE 
      WHEN min_sliding IS NOT NULL 
        AND min_sliding >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
        AND min_sliding < dischtime 
      THEN 1 ELSE 0 
    END) AS num_final48
  FROM insulin_mins
  UNION ALL
  SELECT 
    'basal-bolus' AS regimen,
    COUNT(*) AS total,
    SUM(CASE 
      WHEN min_basal IS NOT NULL AND min_bolus IS NOT NULL
        AND min_basal >= admittime 
        AND min_basal < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
        AND min_bolus >= admittime 
        AND min_bolus < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 
    END) AS num_first72,
    SUM(CASE 
      WHEN min_basal IS NOT NULL AND min_bolus IS NOT NULL
        AND min_basal >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
        AND min_basal < dischtime
        AND min_bolus >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
        AND min_bolus < dischtime
      THEN 1 ELSE 0 
    END) AS num_final48
  FROM insulin_mins
)
SELECT 
  regimen,
  total,
  ROUND(100.0 * num_first72 / total, 2) AS percent_first72,
  ROUND(100.0 * num_final48 / total, 2) AS percent_final48,
  ROUND(ABS(100.0 * (num_first72 - num_final48) / total), 2) AS absolute_percentage_point_difference
FROM counts
ORDER BY 
  CASE regimen 
    WHEN 'basal' THEN 1 
    WHEN 'bolus' THEN 2 
    WHEN 'basal-bolus' THEN 3 
    WHEN 'sliding-scale' THEN 4 
  END;