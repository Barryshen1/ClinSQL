WITH male_adm AS (
  -- male patients aged 57-67 and their admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),

aspirin_pres AS (
  -- aspirin-related inpatient prescription intervals clipped to admission window
  SELECT
    p.subject_id,
    p.hadm_id,
    GREATEST(p.starttime, a.admittime) AS starttime,
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN male_adm a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  WHERE (
        LOWER(COALESCE(p.drug, '')) LIKE '%aspirin%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%acetylsalicylic%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%asa%'
  )
),

p2y12_pres AS (
  -- P2Y12 inhibitor inpatient prescription intervals clipped to admission window
  SELECT
    p.subject_id,
    p.hadm_id,
    GREATEST(p.starttime, a.admittime) AS starttime,
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN male_adm a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  WHERE (
        LOWER(COALESCE(p.drug, '')) LIKE '%clopidogrel%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%plavix%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%prasugrel%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%effient%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%ticagrelor%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%brilinta%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%ticlopidine%'
     OR LOWER(COALESCE(p.drug, '')) LIKE '%ticlid%'
  )
),

overlaps AS (
  -- compute raw overlap intervals between any aspirin and any P2Y12 prescription in same admission
  SELECT
    asp.hadm_id,
    GREATEST(asp.starttime, p2.starttime) AS start_ts,
    LEAST(asp.stoptime, p2.stoptime) AS end_ts
  FROM aspirin_pres asp
  JOIN p2y12_pres p2
    ON asp.subject_id = p2.subject_id
   AND asp.hadm_id = p2.hadm_id
  WHERE asp.starttime < p2.stoptime
    AND p2.starttime < asp.stoptime
),

valid_overlaps AS (
  -- drop null/zero-length overlaps
  SELECT
    hadm_id,
    TIMESTAMP(start_ts) AS start_ts,
    TIMESTAMP(end_ts)   AS end_ts
  FROM overlaps
  WHERE start_ts IS NOT NULL
    AND end_ts IS NOT NULL
    AND TIMESTAMP_DIFF(end_ts, start_ts, SECOND) > 0
),

-- merge/union contiguous or overlapping overlap-intervals into DAPT episodes per admission
numbered AS (
  SELECT
    hadm_id,
    start_ts,
    end_ts,
    LAG(end_ts) OVER (PARTITION BY hadm_id ORDER BY start_ts, end_ts) AS prev_end
  FROM valid_overlaps
),

grp_flag AS (
  SELECT
    hadm_id,
    start_ts,
    end_ts,
    CASE
      WHEN prev_end IS NULL THEN 1
      WHEN start_ts > prev_end THEN 1    -- gap -> new group
      ELSE 0                             -- overlapping/contiguous -> same group
    END AS new_group
  FROM numbered
),

grp AS (
  SELECT
    hadm_id,
    start_ts,
    end_ts,
    SUM(new_group) OVER (PARTITION BY hadm_id ORDER BY start_ts, end_ts
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp_id
  FROM grp_flag
),

merged AS (
  SELECT
    hadm_id,
    MIN(start_ts) AS episode_start,
    MAX(end_ts)   AS episode_end
  FROM grp
  GROUP BY hadm_id, grp_id
),

dapt_episodes AS (
  -- final DAPT episodes with duration in days (float)
  SELECT
    hadm_id,
    episode_start,
    episode_end,
    SAFE_DIVIDE(TIMESTAMP_DIFF(episode_end, episode_start, SECOND), 86400.0) AS duration_days
  FROM merged
),

quantiles AS (
  -- approximate quantiles array (0..100)
  SELECT APPROX_QUANTILES(duration_days, 100) AS q
  FROM dapt_episodes
),

cnt AS (
  SELECT COUNT(*) AS num_dapt_episodes
  FROM dapt_episodes
)

-- compute quartiles and IQR across all DAPT episodes for the selected population
SELECT
  q.q[OFFSET(25)] AS p25_days,
  q.q[OFFSET(75)] AS p75_days,
  q.q[OFFSET(75)] - q.q[OFFSET(25)] AS iqr_days,
  c.num_dapt_episodes
FROM quantiles q
CROSS JOIN cnt c;