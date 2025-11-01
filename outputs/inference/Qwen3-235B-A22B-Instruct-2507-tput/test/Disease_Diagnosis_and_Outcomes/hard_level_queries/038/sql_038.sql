WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.deathtime,
    fa.age_at_admit,
    -- Flag if 30-day mortality
    CASE WHEN p.dod IS NOT NULL 
              AND p.dod <= DATETIME_ADD(fa.admittime, INTERVAL 30 DAY)
         THEN 1 ELSE 0 END AS thirty_day_mortality,
    -- Hospital LOS in days (only valid if discharged)
    DATETIME_DIFF(fa.dischtime, fa.admittime, HOUR) / 24.0 AS los_days,
    -- Join DRG for risk score (drg_mortality)
    COALESCE(drg.drg_mortality, 0) AS drg_mortality,
    -- Flag AKI: ICD-10 code starting with 'N17'
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    -- Flag ARDS: ICD-10 code 'J80'
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON fa.hadm_id = drg.hadm_id AND drg.drg_type = 'APR'
  WHERE fa.age_at_admit BETWEEN 74 AND 84
  GROUP BY fa.subject_id, fa.hadm_id, fa.admittime, fa.dischtime, fa.deathtime, fa.age_at_admit, p.dod, drg.drg_mortality
),
aki_group AS (
  SELECT
    'AKI' AS group_name,
    drg_mortality,
    thirty_day_mortality,
    has_ards,
    los_days
  FROM cohort
  WHERE has_aki = 1
),
non_aki_group AS (
  SELECT
    'Non-AKI' AS group_name,
    drg_mortality,
    thirty_day_mortality,
    has_ards,
    los_days
  FROM cohort
  WHERE has_aki = 0
),
combined AS (
  SELECT * FROM aki_group
  UNION ALL
  SELECT * FROM non_aki_group
),
summary_stats AS (
  SELECT
    group_name,
    -- Median and IQR of risk score (drg_mortality)
    APPROX_QUANTILES(drg_mortality, 100)[OFFSET(50)] AS median_risk,
    APPROX_QUANTILES(drg_mortality, 100)[OFFSET(25)] AS q1_risk,
    APPROX_QUANTILES(drg_mortality, 100)[OFFSET(75)] AS q3_risk,
    -- 30-day mortality rate
    AVG(thirty_day_mortality) AS mortality_rate,
    -- ARDS rate
    AVG(has_ards) AS ards_rate,
    -- Median survivor LOS
    APPROX_QUANTILES(CASE WHEN thirty_day_mortality = 0 THEN los_days END, 100)[OFFSET(50)] AS median_survivor_los
  FROM combined
  GROUP BY group_name
)
SELECT * FROM summary_stats;