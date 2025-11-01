WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 62 AND 72
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    PatientAge AS pa
    ON s.subject_id = pa.subject_id
), HeartRateEvents AS (
  SELECT
    s.stay_id,
    s.charttime,
    s.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS s
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON s.itemid = d.itemid
  WHERE
    d.label = 'Heart Rate'
    AND s.stay_id IN (
      SELECT
        stay_id
      FROM
        ICUStays
    )
), HeartRateCategories AS (
  SELECT
    stay_id,
    CASE
      WHEN heart_rate < 60
      THEN '<60'
      WHEN heart_rate BETWEEN 60 AND 99
      THEN '60–99'
      WHEN heart_rate BETWEEN 100 AND 119
      THEN '100–119'
      ELSE '≥120'
    END AS heart_rate_category
  FROM
    HeartRateEvents
), HeartRateCounts AS (
  SELECT
    stay_id,
    COUNTIF(heart_rate_category = '<60') AS count_lt_60,
    COUNTIF(heart_rate_category = '60–99') AS count_60_99,
    COUNTIF(heart_rate_category = '100–119') AS count_100_119,
    COUNTIF(heart_rate_category = '≥120') AS count_ge_120
  FROM
    HeartRateCategories
  GROUP BY
    stay_id
), AcuteMI AS (
  SELECT
    hadm_id,
    COUNTIF(icd_code = '410') AS acute_mi_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code = '410'
    AND hadm_id IN (
      SELECT
        hadm_id
      FROM
        ICUStays
    )
  GROUP BY
    hadm_id
)
SELECT
  AVG(HeartRateCounts.count_lt_60) AS mean_count_lt_60,
  AVG(HeartRateCounts.count_60_99) AS mean_count_60_99,
  AVG(HeartRateCounts.count_100_119) AS mean_count_100_119,
  AVG(HeartRateCounts.count_ge_120) AS mean_count_ge_120,
  AVG(AcuteMI.acute_mi_count) AS mean_percent_acute_mi
FROM
  HeartRateCounts
LEFT JOIN
  AcuteMI
  ON HeartRateCounts.hadm_id = AcuteMI.hadm_id;