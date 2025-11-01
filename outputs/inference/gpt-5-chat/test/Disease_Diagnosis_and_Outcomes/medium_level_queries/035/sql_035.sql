WITH gi_bleed_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    -- Assign upper / lower flags from ICD codes
    MAX(CASE 
          WHEN (di.icd_version = 10 AND di.icd_code IN ('K92.0','K92.1','K22.6')
                OR (di.icd_version = 10 AND di.icd_code BETWEEN 'K25.0' AND 'K28.0')
                OR (di.icd_version = 9 AND di.icd_code IN ('5780','5781')) 
               )
          THEN 1 ELSE 0 END) AS upper_flag,
    MAX(CASE 
          WHEN (di.icd_version = 10 AND di.icd_code IN ('K92.2','K55.2','K57.0','K57.1','K57.2','K57.3','K57.4','K57.5','K57.9','K62.5')
                OR (di.icd_version = 9 AND di.icd_code IN ('5789','5693'))
               )
          THEN 1 ELSE 0 END) AS lower_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE
      WHEN upper_flag = 1 AND lower_flag = 0 THEN 'Upper GI bleed'
      WHEN lower_flag = 1 AND upper_flag = 0 THEN 'Lower GI bleed'
      ELSE NULL
    END AS gib_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN gi_bleed_flags g
    ON a.subject_id = g.subject_id AND a.hadm_id = g.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
icu_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.gib_type,
    c.los_days,
    c.hospital_expire_flag,
    -- ICU on day 1: intime < admittime + 1 day
    MAX(CASE WHEN icu.intime < DATETIME_ADD(c.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS day1_icu_flag,
    -- ICU ever: any icustay in this hadm
    MAX(1) AS icu_admit_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id AND c.hadm_id = icu.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.gib_type, c.los_days, c.hospital_expire_flag, c.admittime
),
final AS (
  SELECT
    gib_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2 days'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5 days'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9 days'
      WHEN los_days >= 10 THEN '>=10 days'
      ELSE 'Unknown'
    END AS los_bin,
    day1_icu_flag,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct
  FROM icu_flags
  WHERE gib_type IS NOT NULL
  GROUP BY gib_type, los_bin, day1_icu_flag
),
icu_rates AS (
  SELECT
    gib_type,
    ROUND(100 * SUM(icu_admit_flag) / COUNT(*), 2) AS icu_admit_rate_pct
  FROM icu_flags
  WHERE gib_type IS NOT NULL
  GROUP BY gib_type
)
SELECT 
  f.gib_type,
  f.los_bin,
  f.day1_icu_flag,
  f.n_admissions,
  f.deaths,
  f.mortality_pct,
  r.icu_admit_rate_pct
FROM final f
JOIN icu_rates r
  ON f.gib_type = r.gib_type
ORDER BY f.gib_type, f.los_bin, f.day1_icu_flag;