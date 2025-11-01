WITH
-- Identify admissions with AMI (by description OR by common ICD prefixes for ICD-9/ICD-10)
ami_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE
    (
      -- textual match in diagnosis dictionary
      LOWER(COALESCE(dicd.long_title, '')) LIKE '%myocardial infarction%'
      OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%acute myocardial infarction%'
    )
    OR
    (
      -- ICD prefix heuristics for AMI
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),

-- Summarize presence of major complication categories per admission
complications_per_hadm AS (
  SELECT
    d.hadm_id,
    MAX(CASE
          WHEN (
            -- cardiogenic shock: textual OR typical codes (ICD-9 785.5*, ICD-10 R57.0*)
            LOWER(COALESCE(dicd.long_title, '')) LIKE '%cardiogenic shock%'
            OR (d.icd_version = 9 AND d.icd_code LIKE '7855%')
            OR (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'r57%')
          ) THEN 1 ELSE 0 END) AS cardiogenic_shock,
    MAX(CASE
          WHEN (
            -- cardiac arrest: textual OR ICD-9 427.5*, ICD-10 I46*
            LOWER(COALESCE(dicd.long_title, '')) LIKE '%cardiac arrest%'
            OR (d.icd_version = 9 AND d.icd_code LIKE '4275%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I46%')
          ) THEN 1 ELSE 0 END) AS cardiac_arrest,
    MAX(CASE
          WHEN (
            -- heart failure: textual OR ICD-9 428*, ICD-10 I50*
            LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%'
            OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          ) THEN 1 ELSE 0 END) AS heart_failure,
    MAX(CASE
          WHEN (
            -- stroke / cerebrovascular disease: textual OR common ICD prefixes (ICD-9 430-434, ICD-10 I60-I69)
            LOWER(COALESCE(dicd.long_title, '')) LIKE '%stroke%'
            OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%cerebrovascular%'
            OR (d.icd_version = 9 AND (
                  d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR d.icd_code LIKE '436%'
               ))
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
          ) THEN 1 ELSE 0 END) AS stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE d.hadm_id IS NOT NULL
  GROUP BY d.hadm_id
),

-- Main cohort: admissions joined to patients, filtered by age/gender and AMI presence;
-- join complications (left join because some hadm may have no of our listed complications)
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(c.cardiogenic_shock, 0) AS cardiogenic_shock,
    COALESCE(c.cardiac_arrest, 0) AS cardiac_arrest,
    COALESCE(c.heart_failure, 0) AS heart_failure,
    COALESCE(c.stroke, 0) AS stroke,
    -- number of distinct complication categories present (0..4)
    (COALESCE(c.cardiogenic_shock, 0)
     + COALESCE(c.cardiac_arrest, 0)
     + COALESCE(c.heart_failure, 0)
     + COALESCE(c.stroke, 0)
    ) AS num_complications
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ami_hadm am
    ON a.hadm_id = am.hadm_id
  LEFT JOIN complications_per_hadm c
    ON a.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),

-- Compute composite score and assign quintiles (NTILE(5) over composite score)
scored AS (
  SELECT
    *,
    (anchor_age + num_complications) AS composite_score,
    -- quintile 1 = lowest composite scores; quintile 5 = highest
    NTILE(5) OVER (ORDER BY (anchor_age + num_complications) ASC) AS quintile,
    -- length of stay in days (fractional); only defined when admittime AND dischtime present
    CASE
      WHEN admittime IS NOT NULL AND dischtime IS NOT NULL
        THEN TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0
      ELSE NULL
    END AS los_days
  FROM cohort
)

-- Aggregate results by quintile
SELECT
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(CASE WHEN num_complications > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_pct,
  -- approximate median LOS among survivors (hospital_expire_flag = 0); APPROX_QUANTILES returns an array of quantiles
  -- [OFFSET(1)] yields the median when APPROX_QUANTILES(..., 2) is used (0th, median, 100th)
  ROUND(
    SAFE_CAST(
      APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)]
      AS FLOAT64
    ), 3
  ) AS median_survivor_los_days,
  MIN(composite_score) AS composite_score_min,
  MAX(composite_score) AS composite_score_max
FROM scored
GROUP BY quintile
ORDER BY quintile;