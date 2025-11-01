WITH
  -- Filter to female patients aged 77-87 from the hospital module
  female_cohort AS (
    SELECT
      p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE LOWER(p.gender) = 'f'
      AND p.anchor_age BETWEEN 77 AND 87
  ),

  -- Identify relevant ICU stays for that cohort
  stays AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN female_cohort fc
      ON i.subject_id = fc.subject_id
  ),

  -- Pull systolic BP readings within the first 48 hours of each ICU stay
  bp_readings AS (
    SELECT
      s.subject_id,
      s.hadm_id,
      s.stay_id,
      ce.charttime,
      ce.valuenum
    FROM stays AS s
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ce.subject_id = s.subject_id
     AND ce.hadm_id = s.hadm_id
     AND ce.stay_id = s.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%systolic%'
      AND ce.charttime >= s.intime
      AND ce.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
  ),

  -- Compute per-stay average systolic BP over the first 48 hours
  per_stay AS (
    SELECT
      br.subject_id,
      br.hadm_id,
      br.stay_id,
      AVG(br.valuenum) AS avg_systolic_bp
    FROM bp_readings AS br
    GROUP BY br.subject_id, br.hadm_id, br.stay_id
  )

-- Percentile of 160 mmHg within the per-stay averages
SELECT
  100.0 * SAFE_DIVIDE(
    SUM(CASE WHEN ps.avg_systolic_bp <= 160 THEN 1 ELSE 0 END),
    COUNT(*)  -- total number of stays with a computed average
  ) AS percentile_of_160
FROM per_stay AS ps;