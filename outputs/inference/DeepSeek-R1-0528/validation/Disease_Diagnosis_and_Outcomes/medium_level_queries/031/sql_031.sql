WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime, 
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    -- Compute age at admission: anchor_age + (current admission year - anchor_year)
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
),
sepsis_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('995.91', '995.92')) 
             OR (icd_version = 10 AND icd_code IN ('A41.9', 'R65.20')) 
          THEN 1 ELSE 0 
        END) AS sepsis_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code = '785.52') 
             OR (icd_version = 10 AND icd_code = 'R65.21') 
          THEN 1 ELSE 0 
        END) AS shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
base AS (
  SELECT 
    c.*,
    CASE 
      WHEN sf.shock_flag = 1 THEN 'Septic Shock'
      WHEN sf.sepsis_flag = 1 THEN 'Sepsis'
      ELSE NULL 
    END AS condition,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) <= 7 THEN '<=7' 
      ELSE '>7' 
    END AS los_group
  FROM cohort c
  INNER JOIN sepsis_flags sf
    ON c.hadm_id = sf.hadm_id
  WHERE 
    c.age_adm BETWEEN 53 AND 63
    AND (sf.sepsis_flag = 1 OR sf.shock_flag = 1)  -- Only sepsis/septic shock admissions
),
stats AS (
  SELECT 
    condition,
    los_group,
    COUNT(hadm_id) AS n,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    -- Median time-to-death for non-survivors (in days, fractional)
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 1 
           THEN DATETIME_DIFF(deathtime, admittime, HOUR) / 24.0 
           ELSE NULL 
      END, 
      100
    )[OFFSET(50)] AS median_ttd_days
  FROM base
  GROUP BY condition, los_group
),
mortality_pivot AS (
  SELECT 
    condition,
    MAX(IF(los_group = '<=7', mortality_percent, NULL)) AS mortality_le7,
    MAX(IF(los_group = '>7', mortality_percent, NULL)) AS mortality_gt7
  FROM stats
  GROUP BY condition
),
diffs AS (
  SELECT 
    condition,
    mortality_gt7 - mortality_le7 AS absolute_difference,
    (mortality_gt7 - mortality_le7) / NULLIF(mortality_le7, 0) * 100 AS relative_difference
  FROM mortality_pivot
)
SELECT 
  s.condition,
  s.los_group,
  s.n,
  s.mortality_percent,
  s.median_ttd_days,
  d.absolute_difference,
  d.relative_difference
FROM stats s
LEFT JOIN diffs d 
  ON s.condition = d.condition
ORDER BY s.condition, s.los_group;