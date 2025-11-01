WITH cohorts AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = p.subject_id AND i.hadm_id = a.hadm_id
  WHERE UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- Step 2: restrict to cardiogenic shock diagnoses
cardio_shock AS (
  SELECT DISTINCT c.subject_id, c.hadm_id
  FROM cohorts AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE UPPER(di.long_title) LIKE '%CARDIOGENIC SHOCK%'
),

-- Step 3: Final cohort of ICU stays with cardiogenic shock
cohort AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id, c.intime
  FROM cohorts AS c
  JOIN cardio_shock AS cs
    ON c.subject_id = cs.subject_id AND c.hadm_id = cs.hadm_id
),

-- Step 4: Compute first-24h procedure count, LOS, and mortality per admission
per_stay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    -- first 24-hour procedure count
    COALESCE(SUM(
      CASE
        WHEN pe.starttime >= s.intime
             AND pe.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
        THEN 1
        ELSE 0
      END
    ), 0) AS first24hr_proc_count,
    -- hospital LOS in days (fractional)
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) / 86400.0 AS hospital_los_days,
    -- in-hospital mortality indicator
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hospital_mortality
  FROM cohort AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.subject_id = s.subject_id
   AND pe.hadm_id = s.hadm_id
   AND pe.stay_id = s.stay_id
  WHERE a.dischtime IS NOT NULL
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime, a.dischtime, a.admittime, a.hospital_expire_flag
)

-- Step 5: Assign quintiles and summarize by quintile
, quintileised AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    first24hr_proc_count,
    hospital_los_days,
    in_hospital_mortality,
    NTILE(5) OVER (ORDER BY first24hr_proc_count) AS quintile
  FROM per_stay
)

SELECT
  quintile,
  AVG(first24hr_proc_count) AS mean_proc_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(in_hospital_mortality) * 100 AS in_hospital_mortality_percentage
FROM quintileised
GROUP BY quintile
ORDER BY quintile;