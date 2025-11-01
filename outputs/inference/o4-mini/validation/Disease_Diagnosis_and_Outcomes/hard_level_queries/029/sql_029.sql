WITH 
-- 1. Basic hospital cohort of female patients aged 82–92 with pneumonia on admission
pneumonia_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
-- 2. Assign quintiles using anchor_age as a placeholder for the risk score
scored_cohort AS (
  SELECT
    pa.*,
    pa.anchor_age AS risk_score,  -- placeholder; replace with your actual risk score
    NTILE(5) OVER (ORDER BY pa.anchor_age) AS quintile
  FROM
    pneumonia_adm AS pa
),
-- 3. Flag complications and 30‐day mortality, compute LOS
comp_flags AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.quintile,
    sc.admittime,
    sc.dischtime,
    sc.deathtime,
    DATE_DIFF(sc.dischtime, sc.admittime, DAY) AS los,
    -- died within 30 days of discharge
    CASE
      WHEN sc.deathtime IS NOT NULL
       AND sc.deathtime <= DATETIME_ADD(sc.dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS died_30,
    -- cardiovascular complication flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON d2.icd_code = dd2.icd_code
       AND d2.icd_version = dd2.icd_version
      WHERE d2.hadm_id = sc.hadm_id
        AND d2.seq_num > 1
        AND (
             LOWER(dd2.long_title) LIKE '%cardio%'
          OR LOWER(dd2.long_title) LIKE '%heart%'
        )
    ) THEN 1 ELSE 0 END AS pct_cv_complication,
    -- neurologic complication flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d3
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd3
        ON d3.icd_code = dd3.icd_code
       AND d3.icd_version = dd3.icd_version
      WHERE d3.hadm_id = sc.hadm_id
        AND d3.seq_num > 1
        AND (
             LOWER(dd3.long_title) LIKE '%neuro%'
          OR LOWER(dd3.long_title) LIKE '%stroke%'
        )
    ) THEN 1 ELSE 0 END AS pct_neuro_complication
  FROM
    scored_cohort AS sc
)
-- 4. Aggregate by quintile
SELECT
  quintile,
  COUNT(*) AS n_patients,
  ROUND(100 * AVG(died_30), 1)             AS pct_30d_mortality,
  ROUND(100 * AVG(pct_cv_complication), 1) AS pct_cv_complication,
  ROUND(100 * AVG(pct_neuro_complication), 1) AS pct_neuro_complication,
  CAST(
    APPROX_QUANTILES(
      CASE WHEN died_30 = 0 THEN los END
    , 2)[OFFSET(1)] AS INT64
  )                                       AS median_los_survivors_days
FROM
  comp_flags
GROUP BY
  quintile
ORDER BY
  quintile;