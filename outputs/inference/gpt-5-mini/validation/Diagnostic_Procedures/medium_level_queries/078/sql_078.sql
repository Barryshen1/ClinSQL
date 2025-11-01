WITH tia_admissions AS (
  -- admissions for female patients age 88-98 with a TIA diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING (hadm_id, subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    -- filter diagnoses for TIA by matching common text in the diagnosis description
    AND REGEXP_CONTAINS(LOWER(IFNULL(dd.long_title, '')), r'(transient ischemic attack|tia)')
    -- keep admissions within 1-7 days (we will later split into 1-3 vs 4-7)
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 7
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
),

icu_flag AS (
  -- mark admissions with any ICU stay
  SELECT
    hadm_id,
    TRUE AS icu_used
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

imaging_per_hadm AS (
  -- count distinct (chartdate, hcpcs_cd) CT/MRI events per admission based on hcpcsevents + d_hcpcs
  SELECT
    h.hadm_id,
    COUNT(DISTINCT CONCAT(CAST(h.chartdate AS STRING), '||', IFNULL(h.hcpcs_cd, ''))) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    -- match CT/MRI terms in short_description or long_description
    REGEXP_CONTAINS(
      LOWER(CONCAT(IFNULL(d.short_description, ''), ' ', IFNULL(d.long_description, ''))),
      r'(?:\bct\b|\bcomputed tomography\b|\bcomputerized tomography\b|\bcomputerised tomography\b|\bmagnetic resonance\b|\bmri\b)'
    )
  GROUP BY h.hadm_id
),

cohort AS (
  -- assemble per-admission cohort rows with imaging counts and ICU flag and LOS group
  SELECT
    t.hadm_id,
    t.subject_id,
    t.los_days,
    CASE
      WHEN t.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN t.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'other'
    END AS los_group,
    IFNULL(i.imaging_count, 0) AS imaging_count,
    IFNULL(f.icu_used, FALSE) AS icu_used
  FROM
    tia_admissions t
  LEFT JOIN
    imaging_per_hadm i
  USING (hadm_id)
  LEFT JOIN
    icu_flag f
  USING (hadm_id)
  WHERE
    t.los_days BETWEEN 1 AND 7
)

SELECT
  stats.icu_used,
  stats.los_group,
  stats.admissions_n,
  stats.quartiles[OFFSET(1)] AS q25,
  stats.quartiles[OFFSET(2)] AS median,
  stats.quartiles[OFFSET(3)] AS q75
FROM (
  SELECT
    icu_used,
    los_group,
    COUNT(*) AS admissions_n,
    -- APPROX_QUANTILES(..., 4) returns array [min, 25th, 50th, 75th, max]
    APPROX_QUANTILES(imaging_count, 4) AS quartiles
  FROM
    cohort
  GROUP BY icu_used, los_group
) AS stats
ORDER BY
  stats.icu_used DESC,
  stats.los_group;