WITH
-- 1. Get all 70-80yo female admissions
female_70_80 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- 2. Identify PE admissions (ICD-9: 4151x, ICD-10: I26x)
pe_hadm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^4151'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I26'))
    )
),

-- 3. Identify AKI admissions (ICD-9: 584x, ICD-10: N17x)
aki_hadm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^584'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N17'))
    )
),

-- 4. Identify ARDS admissions (ICD-9: 51882, ICD-10: J80)
ards_hadm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      (d.icd_version = 9 AND d.icd_code = '51882')
      OR
      (d.icd_version = 10 AND d.icd_code = 'J80')
    )
),

-- 5. Calculate Charlson Comorbidity Index (CCI) for each admission
-- For brevity, use a simplified CCI calculation (real implementation would be more detailed)
cci_map AS (
  SELECT
    icd_code,
    icd_version,
    CASE
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]')) THEN 1 -- Diabetes
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) THEN 1 -- CHF
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18')) THEN 1 -- Renal
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^414')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I25')) THEN 1 -- MI
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^434')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I63')) THEN 1 -- Stroke
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C')) THEN 2 -- Cancer
      ELSE 0
    END AS cci_points
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
),

cci_per_admission AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(m.cci_points) AS cci
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN cci_map m
      ON d.icd_code = m.icd_code AND d.icd_version = m.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- 6. Combine all info for PE cohort
pe_cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.dod,
    IFNULL(c.cci, 0) AS cci,
    CASE WHEN a.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM
    female_70_80 f
    INNER JOIN pe_hadm p ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
    LEFT JOIN cci_per_admission c ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id
    LEFT JOIN aki_hadm a ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
    LEFT JOIN ards_hadm r ON f.subject_id = r.subject_id AND f.hadm_id = r.hadm_id
),

-- 7. Assign risk-score quintiles
pe_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY cci) AS risk_quintile
  FROM
    pe_cohort
),

-- 8. Calculate outcomes per quintile
pe_quintile_stats AS (
  SELECT
    risk_quintile,
    COUNT(*) AS n,
    SUM(CASE
          WHEN
            -- Death within 90 days of admission
            (
              (dod IS NOT NULL AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 90)
              OR
              (deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 90)
            )
          THEN 1 ELSE 0 END
        ) / COUNT(*) AS mortality_90d_rate,
    SUM(has_aki) / COUNT(*) AS aki_rate,
    SUM(has_ards) / COUNT(*) AS ards_rate,
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(dischtime, admittime, DAY),
      2
    )[OFFSET(1)] AS median_survivor_los
  FROM
    pe_quintiles
  WHERE
    -- Only survivors for LOS
    (
      (dod IS NULL OR TIMESTAMP_DIFF(dod, admittime, DAY) > 90)
      AND
      (deathtime IS NULL OR TIMESTAMP_DIFF(deathtime, admittime, DAY) > 90)
    )
  GROUP BY
    risk_quintile
),

-- 9. General 70-80 female cohort 90-day mortality
general_mortality AS (
  SELECT
    COUNT(*) AS n,
    SUM(CASE
          WHEN
            (
              (dod IS NOT NULL AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 90)
              OR
              (deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 90)
            )
          THEN 1 ELSE 0 END
        ) / COUNT(*) AS mortality_90d_rate
  FROM
    female_70_80
)

-- 10. Final output
SELECT
  q.risk_quintile,
  q.n AS pe_n,
  q.mortality_90d_rate AS pe_90d_mortality,
  g.mortality_90d_rate AS general_90d_mortality,
  q.aki_rate AS pe_aki_rate,
  q.ards_rate AS pe_ards_rate,
  q.median_survivor_los AS pe_median_survivor_los
FROM
  pe_quintile_stats q
  CROSS JOIN general_mortality g
ORDER BY
  q.risk_quintile;