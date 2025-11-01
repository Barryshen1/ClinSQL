WITH 
-- Define medication complexity
medication_complexity AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT p.drug) AS num_unique_meds,
    COUNT(p.pharmacy_id) AS total_medication_orders
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pt ON a.subject_id = pt.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 45 AND 55
    AND a.admission_type = 'Trauma'
    AND p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY 
    a.hadm_id
),

-- Calculate tertiles
tertiles AS (
  SELECT 
    hadm_id,
    num_unique_meds,
    total_medication_orders,
    NTILE(3) OVER (ORDER BY num_unique_meds) AS tertile
  FROM 
    medication_complexity
),

-- Calculate statistics per tertile
stats AS (
  SELECT 
    t.tertile,
    COUNT(DISTINCT t.hadm_id) AS admissions,
    AVG(t.num_unique_meds) AS mean_score,
    MIN(t.num_unique_meds) AS min_score,
    MAX(t.num_unique_meds) AS max_score,
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS mean_LOS,
    SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT t.hadm_id) AS mortality_rate,
    SUM(CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
          WHERE a2.subject_id = a.subject_id 
          AND a2.admittime BETWEEN TIMESTAMP_ADD(a.dischtime, INTERVAL 1 DAY) 
          AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
        ) THEN 1 
        ELSE 0 
      END) / COUNT(DISTINCT t.hadm_id) AS readmission_rate
  FROM 
    tertiles t
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  GROUP BY 
    t.tertile
)

SELECT * FROM stats;