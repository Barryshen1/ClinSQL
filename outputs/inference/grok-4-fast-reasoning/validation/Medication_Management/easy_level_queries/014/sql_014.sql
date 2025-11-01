WITH med_orders AS (
  SELECT 
    p.hadm_id,
    DATE_DIFF(
      COALESCE(p.stoptime, a.dischtime), 
      p.starttime, 
      DAY
    ) + 1 AS order_duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE 
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND UPPER(p.dose_unit_rx) = 'MG'
    AND (LOWER(p.route) LIKE '%oral%' OR LOWER(p.route) LIKE '%po%')
    AND p.starttime >= a.admittime
    AND (p.stoptime IS NULL OR p.stoptime <= a.dischtime)
    AND pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM a.admittime) - pat.anchor_year) BETWEEN 86 AND 96
),
admission_totals AS (
  SELECT 
    hadm_id,
    SUM(order_duration_days) AS total_duration_days
  FROM med_orders
  GROUP BY hadm_id
  HAVING total_duration_days > 0
)
SELECT 
  MIN(total_duration_days) AS min_duration_days
FROM admission_totals;