WITH age_adm AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
first_tnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS tnt_value,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Troponin T high sensitive'  -- Corrected identifier using label
    AND le.valuenum IS NOT NULL
),
qualifying_admissions AS (
  SELECT 
    ft.tnt_value
  FROM age_adm aa
  INNER JOIN first_tnt ft
    ON aa.hadm_id = ft.hadm_id
  WHERE 
    aa.gender = 'F'
    AND aa.age_at_admission BETWEEN 59 AND 69
    AND ft.rn = 1  -- First measurement only
    AND ft.tnt_value > 0.014  -- Initial value > 0.014 ng/mL
),
stats AS (
  SELECT 
    PERCENTILE_CONT(tnt_value, 0.25) OVER () AS p25,
    PERCENTILE_CONT(tnt_value, 0.50) OVER () AS p50,
    PERCENTILE_CONT(tnt_value, 0.75) OVER () AS p75,
    MIN(tnt_value) OVER () AS min_value,
    MAX(tnt_value) OVER () AS max_value
  FROM qualifying_admissions
)
SELECT 
  p25, 
  p50, 
  p75, 
  min_value, 
  max_value
FROM stats
LIMIT 1;