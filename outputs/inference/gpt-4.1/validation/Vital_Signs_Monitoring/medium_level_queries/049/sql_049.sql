WITH female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),

sbp_itemids AS (
  -- Common SBP itemids in MIMIC-IV
  SELECT 51 AS itemid UNION ALL
  SELECT 220179 AS itemid
),

sbp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN sbp_itemids sbi ON ce.itemid = sbi.itemid
  WHERE
    ce.valuenum IS NOT NULL
),

sbp_first_48hr AS (
  SELECT
    f.stay_id,
    AVG(s.valuenum) AS avg_sbp
  FROM
    female_icu_stays f
    JOIN sbp_measurements s
      ON f.stay_id = s.stay_id
      AND s.charttime >= f.intime
      AND s.charttime < DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY
    f.stay_id
  HAVING
    COUNT(s.valuenum) > 0
),

percentile AS (
  SELECT
    COUNTIF(avg_sbp < 130) AS num_below_130,
    COUNT(*) AS total_stays
  FROM
    sbp_first_48hr
)

SELECT
  SAFE_DIVIDE(num_below_130, total_stays) * 100 AS percentile_130mmHg
FROM
  percentile
;