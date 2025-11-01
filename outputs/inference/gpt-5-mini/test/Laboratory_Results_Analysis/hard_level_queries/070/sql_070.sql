WITH
-- Stroke admissions: male, age 40-50, with hemorrhagic stroke ICD-9/ICD-10 codes
stroke_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      -- ICD-10 hemorrhagic stroke codes (nontraumatic I60-I62)
      (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
      OR
      -- ICD-9 hemorrhagic stroke codes (430-432)
      (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430', '431', '432'))
    )
),

-- General inpatient cohort for comparison: male, age 40-50, all admissions
general_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Helper: identify abnormal labevent rows (within 72 hours) for stroke admissions
stroke_lab_abnormal AS (
  SELECT DISTINCT
    sa.hadm_id,
    le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN stroke_admissions sa
    ON le.hadm_id = sa.hadm_id
   AND le.subject_id = sa.subject_id
  WHERE le.charttime IS NOT NULL
    AND le.charttime >= sa.admittime
    AND le.charttime <= TIMESTAMP_ADD(sa.admittime, INTERVAL 72 HOUR)
    AND (
      -- consider abnormal if a flag exists
      (le.flag IS NOT NULL AND TRIM(le.flag) != '')
      -- or if numeric value is outside reference range when numeric and ranges present
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
),

-- Helper: identify abnormal labevent rows (within 72 hours) for general admissions
general_lab_abnormal AS (
  SELECT DISTINCT
    ga.hadm_id,
    le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN general_admissions ga
    ON le.hadm_id = ga.hadm_id
   AND le.subject_id = ga.subject_id
  WHERE le.charttime IS NOT NULL
    AND le.charttime >= ga.admittime
    AND le.charttime <= TIMESTAMP_ADD(ga.admittime, INTERVAL 72 HOUR)
    AND (
      (le.flag IS NOT NULL AND TRIM(le.flag) != '')
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
),

-- Lab instability score per stroke admission: distinct abnormal itemid count within 72h
stroke_scores AS (
  SELECT
    sa.hadm_id,
    sa.subject_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(sa.dischtime, sa.admittime, MINUTE), 1440.0) AS los_days,
    COALESCE(COUNT(DISTINCT sla.itemid), 0) AS lab_instability_score
  FROM stroke_admissions sa
  LEFT JOIN stroke_lab_abnormal sla
    ON sa.hadm_id = sla.hadm_id
  GROUP BY sa.hadm_id, sa.subject_id, sa.admittime, sa.dischtime, sa.hospital_expire_flag
),

-- Assign quartiles (1 = lowest instability, 4 = highest) across stroke cohort
stroke_with_quartile AS (
  SELECT
    ss.*,
    NTILE(4) OVER (ORDER BY ss.lab_instability_score) AS quartile
  FROM stroke_scores ss
),

-- Summary statistics per quartile
quartile_summary AS (
  SELECT
    quartile,
    COUNT(*) AS n_admissions,
    ROUND(AVG(lab_instability_score), 3) AS mean_lab_instability_score,
    ROUND(AVG(los_days), 3) AS mean_los_days,
    -- approximate median LOS via APPROX_QUANTILES
    ROUND((APPROX_QUANTILES(los_days, 2))[OFFSET(1)], 3) AS median_los_days_approx,
    ROUND(AVG(CAST(hospital_expire_flag AS INT64)), 4) AS mortality_rate
  FROM stroke_with_quartile
  GROUP BY quartile
  ORDER BY quartile
),

-- Determine top 10 labs by number of stroke admissions with abnormal result
top_labs AS (
  SELECT
    sla.itemid,
    COUNT(DISTINCT sla.hadm_id) AS n_admissions_with_abnormal
  FROM stroke_lab_abnormal sla
  GROUP BY sla.itemid
  ORDER BY n_admissions_with_abnormal DESC
  LIMIT 10
),

-- Prepare denominators: total admissions per quartile and general total
quartile_denoms AS (
  SELECT
    quartile,
    COUNT(*) AS denom_quartile
  FROM stroke_with_quartile
  GROUP BY quartile
),
general_total AS (
  SELECT COUNT(DISTINCT hadm_id) AS denom_general
  FROM general_admissions
),

-- Per-lab abnormal counts in stroke cohort by quartile for top labs
stroke_lab_rates AS (
  SELECT
    q.quartile,
    tl.itemid,
    COALESCE(d.label, CAST(tl.itemid AS STRING)) AS lab_label,
    COUNT(DISTINCT sla.hadm_id) AS n_abnormal_in_quartile
  FROM top_labs tl
  LEFT JOIN stroke_with_quartile q
    ON TRUE
  LEFT JOIN stroke_lab_abnormal sla
    ON sla.itemid = tl.itemid
   AND sla.hadm_id = q.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON d.itemid = tl.itemid
  GROUP BY q.quartile, tl.itemid, d.label
  ORDER BY q.quartile, n_abnormal_in_quartile DESC
),

-- Per-lab abnormal counts in general cohort for top labs
general_lab_rates AS (
  SELECT
    tl.itemid,
    COALESCE(d.label, CAST(tl.itemid AS STRING)) AS lab_label,
    COUNT(DISTINCT gla.hadm_id) AS n_abnormal_general
  FROM top_labs tl
  LEFT JOIN general_lab_abnormal gla
    ON gla.itemid = tl.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON d.itemid = tl.itemid
  GROUP BY tl.itemid, d.label
)

-- Final combined output: union of quartile summaries and per-lab rates per quartile
SELECT
  'quartile_summary' AS metric_type,
  CAST(qs.quartile AS STRING) AS quartile,
  NULL AS itemid,
  NULL AS lab_label,
  qs.n_admissions AS stroke_n_admissions,
  qs.mean_lab_instability_score,
  qs.mean_los_days,
  qs.median_los_days_approx,
  qs.mortality_rate,
  NULL AS stroke_lab_abnormal_rate,
  NULL AS general_lab_abnormal_rate
FROM quartile_summary qs

UNION ALL

SELECT
  'lab_rate' AS metric_type,
  CAST(slr.quartile AS STRING) AS quartile,
  CAST(slr.itemid AS STRING) AS itemid,
  slr.lab_label AS lab_label,
  qd.denom_quartile AS stroke_n_admissions,
  NULL AS mean_lab_instability_score,
  NULL AS mean_los_days,
  NULL AS median_los_days_approx,
  NULL AS mortality_rate,
  -- stroke rate: n abnormal in quartile / denom_quartile
  ROUND(SAFE_DIVIDE(slr.n_abnormal_in_quartile, qd.denom_quartile), 4) AS stroke_lab_abnormal_rate,
  -- general rate for the same lab: n abnormal general / denom_general
  ROUND(
    SAFE_DIVIDE(
      COALESCE(glr.n_abnormal_general, 0),
      (SELECT denom_general FROM general_total)
    ), 4
  ) AS general_lab_abnormal_rate
FROM stroke_lab_rates slr
LEFT JOIN quartile_denoms qd
  ON qd.quartile = slr.quartile
LEFT JOIN general_lab_rates glr
  ON glr.itemid = slr.itemid
ORDER BY metric_type, quartile, lab_label;