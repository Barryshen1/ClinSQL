WITH base_adms AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - 2008) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime > a.admittime  -- valid LOS
),
aki_adms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE '584%' OR icd_code LIKE 'N17%'
),
eligible AS (
  SELECT 
    b.*,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4' 
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7' 
      ELSE NULL 
    END AS los_group
  FROM base_adms b
  INNER JOIN aki_adms ak 
    ON b.hadm_id = ak.hadm_id
  WHERE age_at_adm BETWEEN 38 AND 48
    AND los_days BETWEEN 1 AND 7
),
with_icu AS (
  SELECT 
    e.*,
    CASE 
      WHEN EXISTS(
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = e.hadm_id
      ) THEN 'With ICU' 
      ELSE 'Without ICU' 
    END AS icu_use
  FROM eligible e
),
with_labs AS (
  SELECT 
    w.*,
    COALESCE(lab_cnt.lab_count, 0) AS num_diagnostics
  FROM with_icu w
  LEFT JOIN (
    SELECT 
      le.hadm_id, 
      COUNT(*) AS lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE le.hadm_id IS NOT NULL
    GROUP BY le.hadm_id
  ) lab_cnt 
    ON w.hadm_id = lab_cnt.hadm_id
)
SELECT 
  los_group,
  icu_use,
  COUNT(*) AS num_admissions,
  ROUND(AVG(num_diagnostics), 2) AS mean_diagnostics,
  MIN(num_diagnostics) AS min_diagnostics,
  MAX(num_diagnostics) AS max_diagnostics
FROM with_labs
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;