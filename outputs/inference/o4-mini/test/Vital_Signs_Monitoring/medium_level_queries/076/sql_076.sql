WITH
-- 1. Filter ICU stays for female patients aged 48-58
filtered_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- 2. Compute per-stay average heart rate in first 48 hours
stay_hr AS (
  SELECT
    fs.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    filtered_stays fs
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    fs.subject_id = ce.subject_id
    AND fs.hadm_id    = ce.hadm_id
    AND fs.stay_id    = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
    AND LOWER(di.label) LIKE '%heart rate%'
  WHERE
    ce.charttime BETWEEN fs.intime
                     AND TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    fs.stay_id
),

-- 3. Determine AKI flag per hospital admission
aki_flags AS (
  SELECT
    diags.hadm_id,
    COUNTIF(LOWER(dlong.long_title) LIKE '%acute kidney injury%') > 0 AS aki_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dlong
  ON
    diags.icd_code    = dlong.icd_code
    AND diags.icd_version = dlong.icd_version
  GROUP BY
    diags.hadm_id
),

-- 4. Combine HR, AKI, and define HR category
stay_summary AS (
  SELECT
    hr.stay_id,
    hr.avg_hr,
    CASE
      WHEN hr.avg_hr < 60    THEN '<60'
      WHEN hr.avg_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN hr.avg_hr BETWEEN 100 AND 119 THEN '100-119'
      ELSE '>=120'
    END AS hr_category,
    -- If no record in aki_flags, treat as no AKI
    IFNULL(af.aki_flag, FALSE) AS aki_flag
  FROM
    stay_hr hr
  LEFT JOIN
    filtered_stays fs
  ON
    hr.stay_id = fs.stay_id
  LEFT JOIN
    aki_flags af
  ON
    fs.hadm_id = af.hadm_id
)

-- 5. Final aggregation: percent distribution and AKI rate by HR category
SELECT
  ss.hr_category,
  COUNT(*) AS stay_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_stays,
  ROUND(  SUM(IF(ss.aki_flag, 1, 0)) * 100.0 / COUNT(*), 1) AS aki_rate_pct
FROM
  stay_summary ss
GROUP BY
  ss.hr_category
ORDER BY
  CASE ss.hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;