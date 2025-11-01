WITH hf_primary_admissions AS (
  -- admissions for female patients age 80-90 at admission with primary diagnosis indicating heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    -- approximate age at admission
    CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) AS age_at_adm,
    -- LOS in days (inclusive)
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) BETWEEN 80 AND 90
    AND d.seq_num = 1
    AND (
      -- ICD-9 heart failure codes (428.*)
      (d.icd_version = 9 AND LOWER(d.icd_code) LIKE '428%')
      -- ICD-10 heart failure codes (I50.*)
      OR (d.icd_version = 10 AND UPPER(d.icd_code) LIKE 'I50%')
      -- or diagnosis description contains "heart failure" (catch misc. mappings)
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
    )
),

bucketed AS (
  -- assign LOS bucket and keep only admissions with positive LOS
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '8+'
      ELSE 'unknown'
    END AS los_bucket
  FROM hf_primary_admissions
  WHERE los_days IS NOT NULL AND los_days >= 1
),

agg AS (
  SELECT
    los_bucket,
    COUNT(*) AS n_total,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_proportion,
    -- approximate median time-to-death in days among decedents (NULL if none)
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 1 AND deathtime IS NOT NULL,
         TIMESTAMP_DIFF(deathtime, admittime, MINUTE) / 1440.0,
         NULL),
      100
    )[OFFSET(50)] AS median_time_to_death_days
  FROM bucketed
  GROUP BY los_bucket
)

SELECT
  los_bucket AS los_group,
  n_total,
  n_deaths,
  -- mortality percent
  ROUND(mortality_proportion * 100, 2) AS mortality_pct,
  -- Wilson 95% CI (percent)
  ROUND(
    CASE
      WHEN n_total > 0 THEN
        (
          -- lower bound
          (
            SAFE_DIVIDE(
              mortality_proportion + (z_sq / (2.0 * n_total)),
              1.0 + SAFE_DIVIDE(z_sq, n_total)
            )
            -
            SAFE_DIVIDE(
              z * SQRT(
                SAFE_DIVIDE(mortality_proportion * (1 - mortality_proportion), n_total)
                + SAFE_DIVIDE(z_sq, 4.0 * n_total * n_total)
              ),
              1.0 + SAFE_DIVIDE(z_sq, n_total)
            )
          )
        )
      ELSE NULL
    END * 100, 2
  ) AS ci_lower_pct,
  ROUND(
    CASE
      WHEN n_total > 0 THEN
        (
          -- upper bound
          (
            SAFE_DIVIDE(
              mortality_proportion + (z_sq / (2.0 * n_total)),
              1.0 + SAFE_DIVIDE(z_sq, n_total)
            )
            +
            SAFE_DIVIDE(
              z * SQRT(
                SAFE_DIVIDE(mortality_proportion * (1 - mortality_proportion), n_total)
                + SAFE_DIVIDE(z_sq, 4.0 * n_total * n_total)
              ),
              1.0 + SAFE_DIVIDE(z_sq, n_total)
            )
          )
        )
      ELSE NULL
    END * 100, 2
  ) AS ci_upper_pct,
  -- median time-to-death in days among in-hospital decedents in the bucket (NULL if no deaths)
  ROUND(median_time_to_death_days, 2) AS median_time_to_death_days
FROM (
  SELECT
    agg.*,
    1.96 AS z,
    1.96 * 1.96 AS z_sq
  FROM agg
) t
ORDER BY
  CASE los_group WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 WHEN '8+' THEN 3 ELSE 4 END;