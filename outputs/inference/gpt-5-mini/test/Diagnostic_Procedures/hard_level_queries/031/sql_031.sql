WITH
-- Identify hospital admissions with HHS (text-based matching on diagnosis description)
hhs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%hyperosmolar%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hhs%'
),

-- Select ICU stays for male patients aged 66-76 whose hospital admission had HHS
cohort_icustays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id AND s.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN hhs_admissions h
    ON s.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
),

-- Compute per-ICU-stay procedure count in the first 48 hours and 30-day readmission flag
per_stay_metrics AS (
  SELECT
    c.*,
    -- Count procedureevents with starttime in [intime, intime + 48 hours]
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.subject_id = c.subject_id
        AND pe.hadm_id = c.hadm_id
        AND pe.stay_id = c.stay_id
        AND pe.starttime IS NOT NULL
        AND pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    ) AS proc_count,
    -- 30-day readmission flag at the admission level (1 if any readmission within 30 days after this admission's dischtime)
    CASE
      WHEN c.dischtime IS NULL THEN 0
      ELSE (
        SELECT CASE WHEN COUNT(1) > 0 THEN 1 ELSE 0 END
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime IS NOT NULL
          AND a2.admittime > c.dischtime
          AND TIMESTAMP_DIFF(a2.admittime, c.dischtime, DAY) <= 30
      )
    END AS readmit_30d_flag
  FROM cohort_icustays c
),

-- Assign quintiles (NTILE) across the distribution of proc_count (ascending)
quintiled AS (
  SELECT
    p.*,
    NTILE(5) OVER (ORDER BY proc_count) AS proc_quintile
  FROM per_stay_metrics p
)

-- Final aggregation per quintile
SELECT
  proc_quintile AS quintile,
  COUNT(1) AS icu_stay_count,
  ROUND(AVG(proc_count), 3) AS mean_procedures_48h,
  MIN(proc_count) AS min_procedures_48h,
  MAX(proc_count) AS max_procedures_48h,
  ROUND(100.0 * SUM(COALESCE(hospital_expire_flag, 0)) / COUNT(1), 2) AS hospital_mortality_percent,
  -- mean hospital LOS in days (fractional). AVG ignores null dischtime values.
  ROUND(AVG(
    CASE
      WHEN admittime IS NOT NULL AND dischtime IS NOT NULL
      THEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
      ELSE NULL
    END
  ), 3) AS mean_hospital_los_days,
  ROUND(100.0 * SUM(COALESCE(readmit_30d_flag, 0)) / COUNT(1), 2) AS readmission_30d_percent
FROM quintiled
GROUP BY proc_quintile
ORDER BY proc_quintile;