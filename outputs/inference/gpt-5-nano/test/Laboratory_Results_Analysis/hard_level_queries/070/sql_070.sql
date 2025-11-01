WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('430','431','432')) OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I6%')
        )
    )
),

-- Step 2: Abnormal labs within 72h for the cohort (per hadm_id, per item)
cohort_labs_abn AS (
  SELECT
    c.hadm_id,
    le.itemid
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = c.hadm_id
  WHERE le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
      (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    )
  GROUP BY c.hadm_id, le.itemid
),

-- Step 3: Instability score per hadm_id (count of distinct abnormal lab itemids within 72h)
cohort_instability AS (
  SELECT hadm_id, COUNT(*) AS instability_score
  FROM cohort_labs_abn
  GROUP BY hadm_id
),

-- Step 4: Attach instability score to cohort and compute quartiles
cohort_with_score AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(s.instability_score, 0) AS instability_score
  FROM cohort AS c
  LEFT JOIN cohort_instability AS s
    ON c.hadm_id = s.hadm_id
),

cohort_with_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM cohort_with_score
),

-- Step 5: LOS and in-hospital mortality by quartile
los_mortality_by_quartile AS (
  SELECT
    instability_quartile,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600.0) AS avg_los_hours,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate,
    COUNT(*) AS n_admissions
  FROM cohort_with_quartile
  GROUP BY instability_quartile
),

-- Step 6: Per-item abnormal rates within 72h for the hemorrhagic cohort
-- Cohort item measurements within 72h (for denominator)
cohort_item_measured AS (
  SELECT le.hadm_id, le.itemid
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = c.hadm_id
  WHERE le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),

-- Cohort: items with an abnormal value within 72h
cohort_item_abn AS (
  SELECT ci.hadm_id, ci.itemid
  FROM cohort_item_measured AS ci
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = ci.hadm_id AND le.itemid = ci.itemid
  WHERE le.valuenum IS NOT NULL
    AND (
      (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    )
  GROUP BY ci.hadm_id, ci.itemid
),

-- Cohort: item-wise denominators (how many cohort admissions had this item measured in first 72h)
cohort_item_denom AS (
  SELECT itemid, COUNT(*) AS denom_cohort
  FROM cohort_item_measured
  GROUP BY itemid
),

-- Cohort: item-wise numerators (how many cohort admissions had abnormal value for this item in first 72h)
cohort_item_abn_count AS (
  SELECT itemid, COUNT(*) AS abn_cohort
  FROM cohort_item_abn
  GROUP BY itemid
),

-- General population denominators and aberrations for first 72h
general_item_measured AS (
  SELECT le.hadm_id, le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = a.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),
general_item_abn AS (
  SELECT gi.itemid, COUNT(*) AS abn_general
  FROM general_item_measured AS gi
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = gi.hadm_id AND le.itemid = gi.itemid
  WHERE le.valuenum IS NOT NULL
    AND (
      (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    )
  GROUP BY gi.itemid
),
general_item_denom AS (
  SELECT itemid, COUNT(*) AS denom_general
  FROM general_item_measured
  GROUP BY itemid
),

-- Combine cohort rates and general rates by item
cohort_rates AS (
  SELECT
    ci.itemid,
    CAST(abn_cohort AS FLOAT64) / NULLIF(CAST(denom_cohort AS FLOAT64), 0) AS rate_cohort
  FROM cohort_item_denom AS ci
  LEFT JOIN cohort_item_abn_count AS ca ON ci.itemid = ca.itemid
),

general_rates AS (
  SELECT
    gi.itemid,
    CAST(abn_general AS FLOAT64) / NULLIF(CAST(denom_general AS FLOAT64), 0) AS rate_general
  FROM general_item_denom AS gi
  LEFT JOIN general_item_abn AS ga ON gi.itemid = ga.itemid
)

SELECT
  di.label AS lab_label,
  cr.rate_cohort AS cohort_abnormal_rate,
  gr.rate_general AS general_abnormal_rate
FROM cohort_rates AS cr
JOIN general_rates AS gr ON cr.itemid = gr.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
  ON cr.itemid = di.itemid
ORDER BY lab_label;