WITH pe_admissions AS (
  -- Female patients age 65-75 with a PE diagnosis on the admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version= dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(dd.long_title) LIKE '%pulmonary embol%'
  GROUP BY
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
),

first_icu_stays AS (
  -- First ICU stay per admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    hospital_expire_flag
  FROM (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      pe.hospital_expire_flag,
      ROW_NUMBER() OVER (
        PARTITION BY icu.subject_id, icu.hadm_id
        ORDER BY icu.intime
      ) AS rn
    FROM
      pe_admissions AS pe
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON pe.subject_id = icu.subject_id
        AND pe.hadm_id    = icu.hadm_id
  )
  WHERE rn = 1
),

proc_counts AS (
  -- Count ICD procedures within 72h of ICU admission
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.los,
    f.hospital_expire_flag,
    COUNT(p.seq_num) AS proc_count
  FROM
    first_icu_stays AS f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
      ON f.subject_id = p.subject_id
      AND f.hadm_id    = p.hadm_id
      AND DATETIME_DIFF(
            DATETIME(p.chartdate),
            f.intime,
            HOUR
          ) BETWEEN 0 AND 72
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.los,
    f.hospital_expire_flag
),

quartiled AS (
  -- Assign quartiles based on procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM
    proc_counts
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*)                         AS N,
  ROUND(AVG(proc_count), 2)       AS mean_proc_count,
  ROUND(AVG(los), 2)               AS mean_icu_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_pct
FROM
  quartiled
GROUP BY
  quartile
ORDER BY
  quartile;