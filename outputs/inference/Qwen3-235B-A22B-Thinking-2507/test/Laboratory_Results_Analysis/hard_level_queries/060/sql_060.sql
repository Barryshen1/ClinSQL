WITH base_admissions AS (
  SELECT
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL  -- Exclude ongoing admissions for LOS/mortality
),
filtered_demographics AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    -- Calculate age at admission (year-level approximation)
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM base_admissions
  WHERE gender = 'F'
    AND anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 52 AND 62
),
cardiac_arrest_cohort AS (
  SELECT
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code = '4275')  -- ICD-9 cardiac arrest
          OR (icd_version = 10 AND icd_code LIKE 'I46.%')  -- ICD-10 cardiac arrest
          THEN 1 ELSE 0 
        END) AS has_cardiac_arrest
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
instability_scores AS (
  SELECT
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    COALESCE(c.has_cardiac_arrest, 0) AS has_cardiac_arrest,
    COUNT(l.labevent_id) AS instability_score  -- Count critical lab events in 48h
  FROM filtered_demographics f
  LEFT JOIN cardiac_arrest_cohort c
    ON f.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.hadm_id = l.hadm_id
    AND l.charttime BETWEEN f.admittime 
                        AND TIMESTAMP_ADD(f.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL  -- Critical lab proxy
  GROUP BY f.hadm_id, f.admittime, f.dischtime, f.hospital_expire_flag, c.has_cardiac_arrest
),
cohort_data AS (
  SELECT
    hadm_id,
    CASE 
      WHEN has_cardiac_arrest = 1 THEN 'cardiac_arrest' 
      ELSE 'general_inpatients' 
    END AS cohort,
    instability_score,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,  -- LOS in days
    hospital_expire_flag AS mortality
  FROM instability_scores
)
SELECT
  cohort,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS instability_score_q1,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS instability_score_median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median_days,
  AVG(mortality) AS mortality_rate
FROM cohort_data
GROUP BY cohort;