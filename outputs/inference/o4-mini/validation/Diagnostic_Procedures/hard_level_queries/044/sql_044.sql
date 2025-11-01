WITH cohort AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON a.subject_id = s.subject_id
   AND a.hadm_id    = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id    = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code    = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(dd.long_title) LIKE '%cardiogenic shock%'
    -- ensure ICU stay is within the hospital admission
    AND s.intime BETWEEN a.admittime AND a.dischtime
),
proc_counts AS (
  SELECT
    c.*,
    (
      SELECT
        COUNT(*)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      WHERE pe.subject_id = c.subject_id
        AND pe.stay_id     = c.stay_id
        AND pe.starttime  >= c.intime
        AND pe.starttime  <  TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    ) AS proc_count
  FROM cohort AS c
),
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts
)
SELECT
  quintile,
  ROUND(AVG(proc_count), 2)      AS mean_proc_count,
  ROUND(AVG(hosp_los), 2)        AS mean_hosp_los,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM quintiled
GROUP BY quintile
ORDER BY quintile;