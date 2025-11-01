WITH sbp_itemids AS (
  -- List of itemids for Systolic BP in MIMIC-IV
  SELECT 220179 AS itemid UNION ALL  -- Non Invasive Blood Pressure systolic
  SELECT 220050 UNION ALL            -- Arterial Blood Pressure systolic
  SELECT 225309                      -- NBP Systolic
),
male_elderly_icu AS (
  -- Get ICU stays for male patients aged 81-91
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
),
sbp_first48 AS (
  -- Get SBP measurements in first 48h of ICU stay
  SELECT
    m.stay_id,
    ce.valuenum
  FROM
    male_elderly_icu m
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON m.stay_id = ce.stay_id
    JOIN sbp_itemids sbi
      ON ce.itemid = sbi.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= m.intime
    AND ce.charttime < DATETIME_ADD(m.intime, INTERVAL 48 HOUR)
),
avg_sbp_per_stay AS (
  -- Compute per-stay average SBP
  SELECT
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM
    sbp_first48
  GROUP BY
    stay_id
),
percentile AS (
  -- Calculate percentile for avg_sbp <= 150
  SELECT
    COUNTIF(avg_sbp <= 150) AS num_le_150,
    COUNT(*) AS total_stays
  FROM
    avg_sbp_per_stay
)
SELECT
  SAFE_DIVIDE(num_le_150, total_stays) * 100 AS percentile_150mmHg
FROM
  percentile
;