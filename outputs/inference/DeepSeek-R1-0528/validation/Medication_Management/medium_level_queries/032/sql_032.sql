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
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') OR 
          (d.icd_version = 10 AND d.icd_code LIKE 'E1%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('428','4280','4281','4282','4283','4284','4289','39891','40201','40211','40291','40401','40403','40411','40413','40491','40493','4254','4255','4257','4258','4259','42820','42821','42822','42823','42830','42831','42832','42833','42840','42841','42842','42843','4289')) OR 
          (d.icd_version = 10 AND d.icd_code IN ('I50','I501','I502','I5020','I5021','I5022','I5023','I503','I5030','I5031','I5032','I5033','I504','I5040','I5041','I5042','I5043','I508','I509','I5081','I5082','I5083','I5084','I5089','I509'))
        )
    )
),

first_24h_orders AS (
  SELECT 
    c.hadm_id,
    p.drug
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE 
    p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND p.stoptime >= c.admittime
    AND LOWER(p.drug) LIKE '%insulin%'
),

final_12h_orders AS (
  SELECT 
    c.hadm_id,
    p.drug
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE 
    p.starttime <= c.dischtime
    AND p.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND LOWER(p.drug) LIKE '%insulin%'
),

first_24h_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%glargine%' OR 
          LOWER(drug) LIKE '%detemir%' OR 
          LOWER(drug) LIKE '%NPH%' OR 
          LOWER(drug) LIKE '%Lantus%' OR 
          LOWER(drug) LIKE '%Levemir%' OR 
          LOWER(drug) LIKE '%Toujeo%' OR 
          LOWER(drug) LIKE '%Basaglar%' 
        THEN 1 ELSE 0 END) AS basal,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%aspart%' OR 
          LOWER(drug) LIKE '%lispro%' OR 
          LOWER(drug) LIKE '%glulisine%' OR 
          LOWER(drug) LIKE '%regular%' OR 
          LOWER(drug) LIKE '%Humalog%' OR 
          LOWER(drug) LIKE '%Novolog%' OR 
          LOWER(drug) LIKE '%Apidra%' 
        THEN 1 ELSE 0 END) AS bolus,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%sliding scale%' OR 
          LOWER(drug) LIKE '%sliding-scale%' OR 
          LOWER(drug) LIKE '%sliding%' OR 
          LOWER(drug) LIKE '%SSI%' OR 
          LOWER(drug) LIKE '%ss insulin%' 
        THEN 1 ELSE 0 END) AS sliding_scale
  FROM cohort c
  LEFT JOIN first_24h_orders f 
    ON c.hadm_id = f.hadm_id
  GROUP BY c.hadm_id
),

final_12h_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%glargine%' OR 
          LOWER(drug) LIKE '%detemir%' OR 
          LOWER(drug) LIKE '%NPH%' OR 
          LOWER(drug) LIKE '%Lantus%' OR 
          LOWER(drug) LIKE '%Levemir%' OR 
          LOWER(drug) LIKE '%Toujeo%' OR 
          LOWER(drug) LIKE '%Basaglar%' 
        THEN 1 ELSE 0 END) AS basal,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%aspart%' OR 
          LOWER(drug) LIKE '%lispro%' OR 
          LOWER(drug) LIKE '%glulisine%' OR 
          LOWER(drug) LIKE '%regular%' OR 
          LOWER(drug) LIKE '%Humalog%' OR 
          LOWER(drug) LIKE '%Novolog%' OR 
          LOWER(drug) LIKE '%Apidra%' 
        THEN 1 ELSE 0 END) AS bolus,
    MAX(CASE WHEN 
          LOWER(drug) LIKE '%sliding scale%' OR 
          LOWER(drug) LIKE '%sliding-scale%' OR 
          LOWER(drug) LIKE '%sliding%' OR 
          LOWER(drug) LIKE '%SSI%' OR 
          LOWER(drug) LIKE '%ss insulin%' 
        THEN 1 ELSE 0 END) AS sliding_scale
  FROM cohort c
  LEFT JOIN final_12h_orders f 
    ON c.hadm_id = f.hadm_id
  GROUP BY c.hadm_id
),

first_24h_summary AS (
  SELECT 
    'Basal_Bolus' AS regimen,
    COUNT(*) AS total_patients,
    SUM(
      CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END
    ) AS count,
    ROUND(
      100 * SUM(CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END) / COUNT(*),
      2
    ) AS percent_first_24h
  FROM first_24h_flags
  UNION ALL
  SELECT 
    'Basal' AS regimen,
    COUNT(*) AS total_patients,
    SUM(basal) AS count,
    ROUND(100 * SUM(basal) / COUNT(*), 2) AS percent_first_24h
  FROM first_24h_flags
  UNION ALL
  SELECT 
    'Bolus' AS regimen,
    COUNT(*) AS total_patients,
    SUM(bolus) AS count,
    ROUND(100 * SUM(bolus) / COUNT(*), 2) AS percent_first_24h
  FROM first_24h_flags
  UNION ALL
  SELECT 
    'Sliding_scale' AS regimen,
    COUNT(*) AS total_patients,
    SUM(sliding_scale) AS count,
    ROUND(100 * SUM(sliding_scale) / COUNT(*), 2) AS percent_first_24h
  FROM first_24h_flags
),

final_12h_summary AS (
  SELECT 
    'Basal_Bolus' AS regimen,
    COUNT(*) AS total_patients,
    SUM(
      CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END
    ) AS count,
    ROUND(
      100 * SUM(CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END) / COUNT(*),
      2
    ) AS percent_final_12h
  FROM final_12h_flags
  UNION ALL
  SELECT 
    'Basal' AS regimen,
    COUNT(*) AS total_patients,
    SUM(basal) AS count,
    ROUND(100 * SUM(basal) / COUNT(*), 2) AS percent_final_12h
  FROM final_12h_flags
  UNION ALL
  SELECT 
    'Bolus' AS regimen,
    COUNT(*) AS total_patients,
    SUM(bolus) AS count,
    ROUND(100 * SUM(bolus) / COUNT(*), 2) AS percent_final_12h
  FROM final_12h_flags
  UNION ALL
  SELECT 
    'Sliding_scale' AS regimen,
    COUNT(*) AS total_patients,
    SUM(sliding_scale) AS count,
    ROUND(100 * SUM(sliding_scale) / COUNT(*), 2) AS percent_final_12h
  FROM final_12h_flags
)

SELECT 
  f24.regimen,
  f24.percent_first_24h,
  f12.percent_final_12h,
  ROUND(f12.percent_final_12h - f24.percent_first_24h, 2) AS percentage_point_change
FROM first_24h_summary f24
INNER JOIN final_12h_summary f12
  ON f24.regimen = f12.regimen
ORDER BY f24.regimen;