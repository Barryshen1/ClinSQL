WITH
-- Filter to male patients aged 64-74 (anchor_age used in MIMIC-IV)
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 64 AND 74
),

-- Admissions for those patients (use explicit alias names to avoid ambiguity)
adms AS (
  SELECT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN male_patients AS mp
    ON adm.subject_id = mp.subject_id
  WHERE adm.hadm_id IS NOT NULL
),

-- Aspirin prescriptions cropped to admission window
aspirin_rx AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    GREATEST(p.starttime, adm.admittime) AS start_ts,
    LEAST(COALESCE(p.stoptime, adm.dischtime), adm.dischtime) AS end_ts
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN adms adm
    ON p.subject_id = adm.subject_id
   AND p.hadm_id = adm.hadm_id
  WHERE LOWER(COALESCE(p.drug, '')) LIKE '%aspirin%'
    -- ensure interval intersects admission
    AND LEAST(COALESCE(p.stoptime, adm.dischtime), adm.dischtime) > GREATEST(p.starttime, adm.admittime)
),

-- P2Y12 inhibitor prescriptions cropped to admission window
p2y12_rx AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    GREATEST(p.starttime, adm.admittime) AS start_ts,
    LEAST(COALESCE(p.stoptime, adm.dischtime), adm.dischtime) AS end_ts
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN adms adm
    ON p.subject_id = adm.subject_id
   AND p.hadm_id = adm.hadm_id
  WHERE (
        LOWER(COALESCE(p.drug, '')) LIKE '%clopidogrel%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%prasugrel%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%ticagrelor%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%ticlopidine%'
  )
  AND LEAST(COALESCE(p.stoptime, adm.dischtime), adm.dischtime) > GREATEST(p.starttime, adm.admittime)
),

-- Pairwise overlaps between any aspirin and any P2Y12 interval within same admission
pairwise_overlaps AS (
  SELECT
    asp.subject_id,
    asp.hadm_id,
    GREATEST(asp.start_ts, p2.start_ts) AS overlap_start,
    LEAST(asp.end_ts, p2.end_ts) AS overlap_end
  FROM aspirin_rx asp
  JOIN p2y12_rx p2
    ON asp.subject_id = p2.subject_id
   AND asp.hadm_id = p2.hadm_id
  WHERE LEAST(asp.end_ts, p2.end_ts) > GREATEST(asp.start_ts, p2.start_ts)  -- positive overlap
),

-- Merge overlapping pairwise intervals per admission to avoid double counting
ordered_overlaps AS (
  SELECT
    subject_id,
    hadm_id,
    overlap_start,
    overlap_end,
    -- previous maximum end among earlier intervals for this admission
    MAX(overlap_end) OVER (
      PARTITION BY subject_id, hadm_id
      ORDER BY overlap_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_max_end
  FROM pairwise_overlaps
),

grouped_overlaps AS (
  SELECT
    subject_id,
    hadm_id,
    overlap_start,
    overlap_end,
    CASE
      WHEN prev_max_end IS NULL OR overlap_start > prev_max_end THEN 1
      ELSE 0
    END AS is_new_group
  FROM ordered_overlaps
),

interval_groups AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_new_group) OVER (PARTITION BY subject_id, hadm_id ORDER BY overlap_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS group_id,
    overlap_start,
    overlap_end
  FROM grouped_overlaps
),

-- For each merged group compute the merged interval (min start, max end)
merged_intervals AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(overlap_start) AS grp_start,
    MAX(overlap_end) AS grp_end
  FROM interval_groups
  GROUP BY subject_id, hadm_id, group_id
),

-- Total concomitant dual-antiplatelet therapy seconds and days per admission
admission_concomitant AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(TIMESTAMP_DIFF(grp_end, grp_start, SECOND)) AS total_seconds,
    SUM(TIMESTAMP_DIFF(grp_end, grp_start, SECOND)) / 86400.0 AS total_days
  FROM merged_intervals
  GROUP BY subject_id, hadm_id
)

-- Final: median (approximate) days among admissions with >0 concomitant days
SELECT
  COUNT(*) AS admissions_with_concomitant_dual_antiplatelet,
  APPROX_QUANTILES(total_days, 100)[OFFSET(50)] AS median_concomitant_days_in_days
FROM admission_concomitant
WHERE total_seconds > 0;