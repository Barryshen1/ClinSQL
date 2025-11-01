WITH first_icu AS (
  -- pick the first ICU stay for each subject
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
),

cohort AS (
  -- restrict to first ICU stay, male patients age 83-93, and admissions with sepsis diagnosis
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM first_icu f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = f.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = f.hadm_id
  WHERE f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      -- require at least one diagnosis for the admission whose long_title mentions "sepsis"
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dx.icd_code = dd.icd_code
       AND dx.icd_version = dd.icd_version
      WHERE dx.hadm_id = f.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%'
    )
),

proc_counts AS (
  -- count distinct procedure icd_code within first 72 hours of ICU intime (per admission)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM cohort c
  LEFT JOIN (
    -- aggregate procedures per admission but only those occurring within 72 hours of ICU intime
    SELECT
      p.hadm_id,
      COUNT(DISTINCT p.icd_code) AS proc_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN cohort c2
      ON p.hadm_id = c2.hadm_id
     -- compare dates to avoid TIMESTAMP vs DATETIME mismatches;
     -- include procedures on the same calendar day as intime through the day of the 72-hour cutoff
    WHERE DATE(p.chartdate) BETWEEN DATE(c2.intime) AND DATE(TIMESTAMP_ADD(c2.intime, INTERVAL 72 HOUR))
      AND p.icd_code IS NOT NULL
    GROUP BY p.hadm_id
  ) pc
  ON pc.hadm_id = c.hadm_id
),

with_quartile AS (
  -- assign quartiles based on proc_count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM proc_counts
)

-- final aggregation per quartile
SELECT
  quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 3) AS mean_proc_count,
  ROUND(AVG(los), 3) AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;