WITH lower_gi_hadm AS (
  -- Identify hospital admissions with a diagnosis indicative of lower GI bleeding
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    USING(icd_code, icd_version)
  WHERE (
    LOWER(dd.long_title) LIKE '%rectal%'
    OR LOWER(dd.long_title) LIKE '%rectum%'
    OR LOWER(dd.long_title) LIKE '%hematochezia%'
    OR (LOWER(dd.long_title) LIKE '%lower%' AND LOWER(dd.long_title) LIKE '%gastrointestinal%')
    OR LOWER(dd.long_title) LIKE '%lower gastrointestinal%'
  )
),

first_icu_per_admission AS (
  -- Select first ICU stay per hospital admission (hadm_id)
  SELECT *
  FROM (
    SELECT
      icu.*,
      a.hospital_expire_flag,
      p.anchor_age,
      ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON icu.hadm_id = a.hadm_id AND icu.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN lower_gi_hadm lg
      ON icu.hadm_id = lg.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 87 AND 97
  )
  WHERE rn = 1
),

proc_counts AS (
  -- Count distinct procedures (procedureevents.itemid) within first 48 hours of ICU stay
  SELECT
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    f.intime,
    f.outtime,
    f.los,
    f.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu_per_admission f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id
   AND f.hadm_id = pe.hadm_id
   AND pe.starttime IS NOT NULL
   AND pe.starttime >= f.intime
   AND pe.starttime <= TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY
    f.stay_id, f.subject_id, f.hadm_id, f.intime, f.outtime, f.los, f.hospital_expire_flag
),

with_quintiles AS (
  -- Assign quintiles by procedure count
  SELECT
    pc.*,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts pc
)

-- Aggregate results by quintile
SELECT
  quintile,
  COUNT(*) AS n_stays,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  ROUND(AVG(los), 3) AS mean_icu_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS inhospital_mortality_pct
FROM with_quintiles
GROUP BY quintile
ORDER BY quintile;