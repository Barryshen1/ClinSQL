WITH cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS icu_los_days,
    -- Age calculation: approximate using anchor_year and anchor_age
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 78 AND 88
),
hhs_diagnoses AS (
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_code IN ('E10.22', 'E11.22')  -- ICD-10 codes for HHS
),
cohort_with_hhs AS (
  SELECT
    c.*
  FROM
    cohort c
  INNER JOIN
    hhs_diagnoses h
    ON c.hadm_id = h.hadm_id
),
vitals_24h AS (
  SELECT
    c.stay_id,
    c.intime,
    ce.charttime,
    ce.valuenum,
    ce.itemid
  FROM
    cohort_with_hhs c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 24 HOUR
    AND ce.itemid IN (211, 456, 220)  -- HR (211), MAP (456), RR (220)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude non-positive values
),
vitals_agg AS (
  SELECT
    stay_id,
    itemid,
    AVG(valuenum) AS mean,
    STDDEV(valuenum) AS std_dev
  FROM
    vitals_24h
  GROUP BY
    stay_id, itemid
),
vitals_pivot AS (
  SELECT
    stay_id,
    SUM(CASE WHEN itemid = 211 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END) AS hr_cv,
    SUM(CASE WHEN itemid = 456 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END) AS map_cv,
    SUM(CASE WHEN itemid = 220 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END) AS rr_cv,
    (SUM(CASE WHEN itemid = 211 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END) +
     SUM(CASE WHEN itemid = 456 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END) +
     SUM(CASE WHEN itemid = 220 THEN (std_dev / NULLIF(mean, 0)) * 100 ELSE 0 END)) AS instability_score
  FROM
    vitals_agg
  GROUP BY
    stay_id
),
abnormal_vitals AS (
  SELECT
    c.stay_id,
    COUNT(*) AS abnormal_vital_count
  FROM
    cohort_with_hhs c
  INNER JOIN
    vitals_24h v
    ON c.stay_id = v.stay_id
  WHERE
    (v.itemid = 211 AND (v.valuenum < 40 OR v.valuenum > 130)) OR  -- HR thresholds
    (v.itemid = 456 AND (v.valuenum < 50 OR v.valuenum > 160)) OR  -- MAP thresholds
    (v.itemid = 220 AND (v.valuenum < 8 OR v.valuenum > 30))       -- RR thresholds
  GROUP BY
    c.stay_id
),
main_metrics AS (
  SELECT
    c.stay_id,
    c.age,
    c.icu_los_days,
    c.hospital_expire_flag,
    v.instability_score,
    a.abnormal_vital_count
  FROM
    cohort_with_hhs c
  LEFT JOIN
    vitals_pivot v
    ON c.stay_id = v.stay_id
  LEFT JOIN
    abnormal_vitals a
    ON c.stay_id = a.stay_id
),
instability_quartile AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM
    main_metrics
  WHERE
    instability_score IS NOT NULL  -- Exclude stays without complete vital signs
)
SELECT
  stay_id,
  instability_score,
  decile,
  abnormal_vital_count,
  icu_los_days,
  hospital_expire_flag AS in_hospital_mortality
FROM
  instability_quartile
WHERE
  quartile = 1  -- Top quartile (highest 25% by instability_score)
ORDER BY
  instability_score DESC;