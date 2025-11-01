WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime,  -- Not used in final output but needed for age calculation
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_admissions AS (
  SELECT 
    pa.hadm_id, 
    pa.age_at_admission
  FROM patient_admissions pa
  WHERE pa.age_at_admission BETWEEN 54 AND 64
),
lab_troponin AS (
  SELECT 
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_t_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 51003  -- Troponin-T itemid
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
first_troponin AS (
  SELECT 
    lt.hadm_id,
    lt.troponin_t_value,
    ROW_NUMBER() OVER (PARTITION BY lt.hadm_id ORDER BY lt.charttime) AS rn
  FROM lab_troponin lt
  INNER JOIN filtered_admissions fa
    ON lt.hadm_id = fa.hadm_id
),
initial_high_troponin_admissions AS (
  SELECT 
    ft.hadm_id,
    ft.troponin_t_value AS initial_troponin
  FROM first_troponin ft
  WHERE ft.rn = 1  -- First Troponin-T measurement
    AND ft.troponin_t_value > 0.01
),
stats AS (
  SELECT 
    COUNT(initial_troponin) AS n,
    AVG(initial_troponin) AS mean,
    STDDEV(initial_troponin) AS sd,
    MIN(initial_troponin) AS min,
    MAX(initial_troponin) AS max,
    APPROX_QUANTILES(initial_troponin, 100) AS quantiles
  FROM initial_high_troponin_admissions
)
SELECT 
  n,
  mean,
  sd,
  min,
  max,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS median,
  quantiles[OFFSET(75)] AS p75
FROM stats;