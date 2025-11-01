WITH
-- 1. Get all admissions for male patients aged 71-81
adm_pat AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- 2. Identify DVT admissions (ICD-9: 453.x, ICD-10: I82.x)
dvt_adm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^453'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I82'))
    )
),

-- 3. Calculate Charlson Comorbidity Index (CCI) per admission
-- Map ICD codes to CCI weights (simplified for demonstration)
cci_map AS (
  SELECT 'I10' AS icd_code, 10 AS icd_version, 1 AS weight UNION ALL -- Hypertension
  SELECT 'I25', 10, 1 UNION ALL -- Chronic ischemic heart disease
  SELECT 'I50', 10, 1 UNION ALL -- Heart failure
  SELECT 'I63', 10, 1 UNION ALL -- Stroke
  SELECT 'E11', 10, 1 UNION ALL -- Diabetes
  SELECT 'C34', 10, 2 UNION ALL -- Cancer
  SELECT 'N18', 10, 2 UNION ALL -- CKD
  SELECT 'B20', 10, 6 UNION ALL -- AIDS
  SELECT '428', 9, 1 UNION ALL -- Heart failure
  SELECT '250', 9, 1 UNION ALL -- Diabetes
  SELECT '434', 9, 1 UNION ALL -- Stroke
  SELECT '585', 9, 2 UNION ALL -- CKD
  SELECT '042', 9, 6 UNION ALL -- AIDS
  SELECT '140', 9, 2 -- Cancer
),
cci_per_adm AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(m.weight) AS cci
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN cci_map m
      ON d.icd_code = m.icd_code AND d.icd_version = m.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- 4. DVT cohort with high comorbidity (CCI >= 3)
dvt_high_cci AS (
  SELECT
    ap.*,
    cci_per_adm.cci
  FROM
    adm_pat ap
    JOIN dvt_adm dvt
      ON ap.subject_id = dvt.subject_id AND ap.hadm_id = dvt.hadm_id
    JOIN cci_per_adm
      ON ap.subject_id = cci_per_adm.subject_id AND ap.hadm_id = cci_per_adm.hadm_id
  WHERE
    cci_per_adm.cci >= 3
),

-- 5. Major complication ICD codes (PE, major bleeding, sepsis, stroke, MI)
major_comp_icd AS (
  SELECT 'I26' AS icd_code, 10 AS icd_version UNION ALL -- PE
  SELECT 'I61', 10 UNION ALL -- Intracerebral hemorrhage
  SELECT 'I63', 10 UNION ALL -- Stroke
  SELECT 'I21', 10 UNION ALL -- MI
  SELECT 'A41', 10 UNION ALL -- Sepsis
  SELECT '430', 9 UNION ALL -- Subarachnoid hemorrhage
  SELECT '431', 9 UNION ALL -- Intracerebral hemorrhage
  SELECT '410', 9 UNION ALL -- MI
  SELECT '038', 9 -- Sepsis
),
-- Admissions with major complication
adm_major_comp AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN major_comp_icd m
      ON d.icd_code = m.icd_code AND d.icd_version = m.icd_version
),

-- 6. General inpatients aged 71-81 (for comparison)
gen_adm_pat AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 71 AND 81
),

-- 7. General inpatients with major complication
gen_major_comp AS (
  SELECT
    g.subject_id,
    g.hadm_id
  FROM
    gen_adm_pat g
    JOIN adm_major_comp c
      ON g.subject_id = c.subject_id AND g.hadm_id = c.hadm_id
),

-- 8. LOS calculations (in days)
dvt_survivor_los AS (
  SELECT
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM
    dvt_high_cci
  WHERE
    hospital_expire_flag = 0
),
gen_survivor_los AS (
  SELECT
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM
    gen_adm_pat
  WHERE
    hospital_expire_flag = 0
),

-- 9. 90-day mortality for DVT/high CCI cohort
dvt_90d_mortality AS (
  SELECT
    hadm_id,
    CASE
      WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, dischtime, DAY) BETWEEN 0 AND 90 THEN 1
      ELSE 0
    END AS died_90d
  FROM
    dvt_high_cci
),

-- 10. Risk percentile for the specific patient (76-year-old man with DVT)
target_patient AS (
  SELECT
    subject_id,
    hadm_id,
    cci
  FROM
    dvt_high_cci
  WHERE
    anchor_age = 76
  ORDER BY admittime
  LIMIT 1
),
risk_percentile AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.cci,
    ROUND(100.0 * (
      SELECT COUNT(*) FROM dvt_high_cci WHERE cci < t.cci
    ) / (SELECT COUNT(*) FROM dvt_high_cci), 1) AS risk_percentile
  FROM
    target_patient t
)

-- Final output
SELECT
  -- DVT/high CCI cohort stats
  (SELECT APPROX_QUANTILES(cci, 4)[OFFSET(2)] FROM dvt_high_cci) AS median_risk_score,
  (SELECT APPROX_QUANTILES(cci, 4)[OFFSET(1)] FROM dvt_high_cci) AS risk_score_q1,
  (SELECT APPROX_QUANTILES(cci, 4)[OFFSET(3)] FROM dvt_high_cci) AS risk_score_q3,
  (SELECT ROUND(100.0 * SUM(died_90d) / COUNT(*), 1) FROM dvt_90d_mortality) AS dvt_90d_mortality_rate_percent,
  (SELECT ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dvt_high_cci), 1)
   FROM dvt_high_cci dhc
   JOIN adm_major_comp amc ON dhc.subject_id = amc.subject_id AND dhc.hadm_id = amc.hadm_id
  ) AS dvt_major_complication_rate_percent,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(2)] FROM dvt_survivor_los) AS dvt_survivor_los_median,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(1)] FROM dvt_survivor_los) AS dvt_survivor_los_q1,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(3)] FROM dvt_survivor_los) AS dvt_survivor_los_q3,

  -- General inpatient stats
  (SELECT ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM gen_adm_pat), 1)
   FROM gen_major_comp
  ) AS gen_major_complication_rate_percent,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(2)] FROM gen_survivor_los) AS gen_survivor_los_median,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(1)] FROM gen_survivor_los) AS gen_survivor_los_q1,
  (SELECT APPROX_QUANTILES(los, 4)[OFFSET(3)] FROM gen_survivor_los) AS gen_survivor_los_q3,

  -- Target patient risk percentile
  (SELECT risk_percentile FROM risk_percentile) AS target_patient_risk_percentile;