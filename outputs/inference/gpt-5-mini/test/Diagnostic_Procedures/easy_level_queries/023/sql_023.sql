WITH female_admissions AS (
  -- female hospital admissions for patients aged 82-92 (inclusive)
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

cardiac_procedures AS (
  -- select procedures whose description suggests a cardiac procedure
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code,
    pi.icd_version,
    dp.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    pi.icd_code = dp.icd_code
    AND pi.icd_version = dp.icd_version
  WHERE
    dp.long_title IS NOT NULL
    AND (
      LOWER(dp.long_title) LIKE '%cardi%' OR
      LOWER(dp.long_title) LIKE '%heart%' OR
      LOWER(dp.long_title) LIKE '%coronar%' OR
      LOWER(dp.long_title) LIKE '%cabg%' OR
      LOWER(dp.long_title) LIKE '%bypass%' OR
      LOWER(dp.long_title) LIKE '%pacemaker%' OR
      LOWER(dp.long_title) LIKE '%valve%' OR
      LOWER(dp.long_title) LIKE '%stent%' OR
      LOWER(dp.long_title) LIKE '%angioplast%' OR
      LOWER(dp.long_title) LIKE '%arrhythm%'
    )
),

per_admission_counts AS (
  -- count distinct cardiac procedure codes per hadm_id, include zeros via LEFT JOIN
  SELECT
    fa.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN c.icd_code IS NOT NULL THEN
          CONCAT(
            COALESCE(CAST(c.icd_version AS STRING), ''),
            '|',
            COALESCE(c.icd_code, '')
          )
        ELSE NULL
      END
    ) AS num_distinct_cardiac_procs
  FROM
    female_admissions fa
  LEFT JOIN
    cardiac_procedures c
  USING(hadm_id)
  GROUP BY
    fa.hadm_id
)

-- compute the 25th percentile (approximate) of distinct cardiac procedures per hospitalization
SELECT
  APPROX_QUANTILES(num_distinct_cardiac_procs, 100)[OFFSET(25)] AS percentile_25_distinct_cardiac_procs_per_hadm,
  COUNT(*) AS num_hospitalizations_considered
FROM
  per_admission_counts;