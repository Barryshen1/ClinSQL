WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN (
    SELECT DISTINCT
      subject_id,
      stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (220339, 225456, 225457, 225467, 225468)
  ) r
    ON i.subject_id = r.subject_id
    AND i.stay_id = r.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
vitals AS (
  SELECT
    c.stay_id,
    COUNT(ce.itemid) AS total_vitals,
    SUM(
      CASE
        WHEN ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
        WHEN ce.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
        WHEN ce.itemid = 220180 AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
        WHEN ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 25) THEN 1
        WHEN ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1
        ELSE 0
      END
    ) AS abnormal_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220179, 220180, 220210, 223762)
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
scores AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COALESCE(
      v.abnormal_count * 100.0 / NULLIF(v.total_vitals, 0),
      0
    ) AS score
  FROM cohort c
  LEFT JOIN vitals v
    ON c.stay_id = v.stay_id
),
ranked AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY score DESC) AS decile
  FROM scores
)
SELECT
  ROUND(
    (COUNTIF(score <= 65) * 100.0 / COUNT(*)),
    2
  ) AS percentile_of_65,
  ROUND(
    AVG(CASE WHEN decile = 1 THEN los END),
    2
  ) AS mean_los_top_decile,
  ROUND(
    AVG(CASE WHEN decile = 1 THEN hospital_expire_flag END),
    4
  ) AS mortality_top_decile
FROM ranked;