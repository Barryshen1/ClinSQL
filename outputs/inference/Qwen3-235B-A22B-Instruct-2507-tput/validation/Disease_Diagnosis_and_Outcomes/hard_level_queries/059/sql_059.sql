WITH base_population AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    -- 30-day mortality: if died within 30 days of admission
    CASE 
      WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS thirty_day_mortality,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
dka_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('E10.1', 'E11.1', 'E13.1')  -- DKA codes
),
aki_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'N17.%'
),
ards_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code = 'J80'
),
drg_severity AS (
  SELECT 
    hadm_id,
    drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp`.drgcodes
  WHERE drg_type = 'APR'  -- Use APR DRG for severity; more standardized
),
cohort AS (
  SELECT 
    bp.*,
    drg.drg_severity,
    CASE WHEN dka.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_dka,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM base_population bp
  LEFT JOIN dka_codes dka ON bp.hadm_id = dka.hadm_id
  LEFT JOIN aki_codes aki ON bp.hadm_id = aki.hadm_id
  LEFT JOIN ards_codes ards ON bp.hadm_id = ards.hadm_id
  LEFT JOIN drg_severity drg ON bp.hadm_id = drg.hadm_id
),
-- Compute percentile ranks of drg_severity within the non-DKA (control) group
percentile_ranks AS (
  SELECT
    hadm_id,
    drg_severity,
    is_dka,
    -- Compute cumulative distribution for non-DKA patients
    IF(
      is_dka = 0 AND drg_severity IS NOT NULL,
      PERCENT_RANK() OVER (ORDER BY drg_severity),
      NULL
    ) AS control_percentile
  FROM cohort
  WHERE drg_severity IS NOT NULL
),
-- For each DKA patient, find their percentile within the control (non-DKA) distribution
dka_with_control_percentile AS (
  SELECT
    c.hadm_id,
    c.drg_severity,
    -- Approximate percentile: fraction of control group with lower severity
    SUM(CASE WHEN pr.drg_severity < c.drg_severity THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_in_controls
  FROM cohort c
  CROSS JOIN percentile_ranks pr
  WHERE c.is_dka = 1 AND c.drg_severity IS NOT NULL
    AND pr.is_dka = 0 AND pr.drg_severity IS NOT NULL
  GROUP BY c.hadm_id, c.drg_severity
),
summary_stats AS (
  SELECT
    is_dka,
    AVG(drg_severity) AS mean_drg_severity,
    AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    AVG(CASE WHEN thirty_day_mortality = 0 THEN los_days END) AS mean_survivor_los
  FROM cohort
  WHERE drg_severity IS NOT NULL  -- Only include admissions with severity score
  GROUP BY is_dka
)
-- Final output: combine DKA and non-DKA stats, add percentile for DKA group
SELECT
  s.is_dka,
  s.mean_drg_severity,
  s.thirty_day_mortality_rate,
  s.aki_rate,
  s.ards_rate,
  s.mean_survivor_los,
  -- For DKA group, add average percentile within control group
  CASE 
    WHEN s.is_dka = 1 THEN AVG(d.percentile_in_controls)
    ELSE NULL 
  END AS drg_severity_percentile_in_matched_controls
FROM summary_stats s
LEFT JOIN dka_with_control_percentile d ON s.is_dka = 1
GROUP BY s.is_dka, s.mean_drg_severity, s.thirty_day_mortality_rate, s.aki_rate, s.ards_rate, s.mean_survivor_los
ORDER BY s.is_dka DESC;