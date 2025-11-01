WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),

aki_flags AS (
  SELECT DISTINCT hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND icd_code LIKE 'N17%')
),

icu_female_elderly AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icustays.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
),

first24_spo2 AS (
  SELECT
    ie.hadm_id,
    c.stay_id,
    AVG(c.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_female_elderly ie
    ON c.subject_id = ie.subject_id
   AND c.hadm_id    = ie.hadm_id
   AND c.stay_id    = ie.stay_id
  WHERE c.itemid IN (SELECT itemid FROM spo2_items)
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN ie.intime
                       AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.hadm_id, c.stay_id
),

spo2_bins AS (
  SELECT
    f.stay_id,
    f.hadm_id,
    f.avg_spo2,
    CASE
      WHEN f.avg_spo2 < 90    THEN '<90'
      WHEN f.avg_spo2 <= 92   THEN '90-92'
      WHEN f.avg_spo2 <= 95   THEN '93-95'
      ELSE '>95'
    END AS spo2_bin
  FROM first24_spo2 f
)

SELECT
  sb.spo2_bin,
  COUNT(*)                                   AS N,
  ROUND(AVG(sb.avg_spo2), 2)                AS mean_avg_spo2,
  APPROX_QUANTILES(sb.avg_spo2, 4)[OFFSET(2)] AS median_avg_spo2,
  ROUND(
    APPROX_QUANTILES(sb.avg_spo2, 4)[OFFSET(3)]
    - APPROX_QUANTILES(sb.avg_spo2, 4)[OFFSET(1)]
    , 2
  )                                          AS iqr_avg_spo2,
  ROUND(
    100 * SUM(IF(af.aki_flag = 1, 1, 0)) / COUNT(*)
    , 1
  )                                          AS aki_rate_percent
FROM spo2_bins sb
LEFT JOIN aki_flags af
  ON sb.hadm_id = af.hadm_id
GROUP BY sb.spo2_bin
ORDER BY
  CASE sb.spo2_bin
    WHEN '<90'   THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95'   THEN 4
  END;