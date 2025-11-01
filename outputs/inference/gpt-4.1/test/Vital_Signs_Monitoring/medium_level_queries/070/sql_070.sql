WITH spo2_items AS (
  -- Find all itemids for SpO2 in ICU
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),

cohort AS (
  -- Female ICU patients aged 90-100
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 90 AND 100
),

spo2_first24h AS (
  -- Get all SpO2 measurements in first 24h of ICU stay
  SELECT
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

spo2_avg_per_stay AS (
  -- Compute average SpO2 per stay (first 24h)
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    AVG(valuenum) AS avg_spo2
  FROM spo2_first24h
  GROUP BY stay_id, hadm_id, subject_id
),

aki_stays AS (
  -- Identify stays with AKI diagnosis (N17.x ICD-10)
  SELECT DISTINCT
    icu.stay_id
  FROM spo2_avg_per_stay icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  WHERE
    (
      (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
      OR
      (dx.icd_version = 9 AND dx.icd_code IN ('584', '5845', '5846', '5847', '5848', '5849'))
    )
),

binned AS (
  -- Bin average SpO2 per stay
  SELECT
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    s.avg_spo2,
    CASE
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 >= 90 AND s.avg_spo2 < 93 THEN '90-92'
      WHEN s.avg_spo2 >= 93 AND s.avg_spo2 <= 95 THEN '93-95'
      WHEN s.avg_spo2 > 95 THEN '>95'
      ELSE 'Unknown'
    END AS spo2_bin,
    CASE WHEN a.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM spo2_avg_per_stay s
  LEFT JOIN aki_stays a
    ON s.stay_id = a.stay_id
  WHERE s.avg_spo2 IS NOT NULL
)

SELECT
  spo2_bin,
  COUNT(*) AS N,
  ROUND(AVG(avg_spo2), 2) AS mean_spo2,
  ROUND(APPROX_QUANTILES(avg_spo2, 2)[OFFSET(1)], 2) AS median_spo2,
  ROUND(APPROX_QUANTILES(avg_spo2, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(avg_spo2, 4)[OFFSET(3)], 2) AS iqr_75,
  ROUND(SUM(has_aki) / COUNT(*), 4) AS aki_rate
FROM binned
WHERE spo2_bin != 'Unknown'
GROUP BY spo2_bin
ORDER BY
  CASE spo2_bin
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;