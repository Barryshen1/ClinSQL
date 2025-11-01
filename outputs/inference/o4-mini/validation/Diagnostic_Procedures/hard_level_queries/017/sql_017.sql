WITH first_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort AS (
  -- Male patients age 83–93 on first ICU stay with sepsis diagnosis
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime,
    fs.los,
    adm.hospital_expire_flag
  FROM
    first_stays fs
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fs.hadm_id = adm.hadm_id
  WHERE
    fs.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = fs.subject_id
        AND d.hadm_id = fs.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%'
    )
),
proc_counts AS (
  -- Count distinct procedures in first 72 hours post ICU intake
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT pi.icd_code) AS proc_count,
    c.los,
    c.hospital_expire_flag
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pi.subject_id = c.subject_id
    AND pi.hadm_id = c.hadm_id
    AND TIMESTAMP_DIFF(
          TIMESTAMP(pi.chartdate),
          TIMESTAMP(c.intime),
          HOUR
        ) BETWEEN 0 AND 71
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    c.hospital_expire_flag
),
quartiled AS (
  -- Assign quartiles based on proc_count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM
    proc_counts
)
-- Final aggregation by quartile
SELECT
  quartile,
  ROUND(AVG(proc_count), 2)                       AS mean_proc_count,
  ROUND(AVG(los), 2)                              AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM
  quartiled
GROUP BY
  quartile
ORDER BY
  quartile;