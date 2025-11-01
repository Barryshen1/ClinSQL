WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 80 AND 90
), ICUStays AS (
  SELECT
    p.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON a.hadm_id = ic.hadm_id
  INNER JOIN
    PatientAge AS p
    ON a.subject_id = p.subject_id
), HeartRateEvents AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    ICUStays AS ic
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.subject_id = ce.subject_id AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220176 -- Heart Rate
), AvgHeartRatePerStay AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS avg_heart_rate
  FROM
    HeartRateEvents
  GROUP BY
    stay_id
), PercentileCalculation AS (
  SELECT
    avg_heart_rate,
    PERCENTILE_CONT(avg_heart_rate, 0.90) OVER (ORDER BY avg_heart_rate) AS p90,
    PERCENTILE_CONT(avg_heart_rate, 0.80) OVER (ORDER BY avg_heart_rate) AS p80,
    PERCENTILE_CONT(avg_heart_rate, 0.70) OVER (ORDER BY avg_heart_rate) AS p70,
    PERCENTILE_CONT(avg_heart_rate, 0.60) OVER (ORDER BY avg_heart_rate) AS p60,
    PERCENTILE_CONT(avg_heart_rate, 0.50) OVER (ORDER BY avg_heart_rate) AS p50,
    PERCENTILE_CONT(avg_heart_rate, 0.40) OVER (ORDER BY avg_heart_rate) AS p40,
    PERCENTILE_CONT(avg_heart_rate, 0.30) OVER (ORDER BY avg_heart_rate) AS p30,
    PERCENTILE_CONT(avg_heart_rate, 0.20) OVER (ORDER BY avg_heart_rate) AS p20,
    PERCENTILE_CONT(avg_heart_rate, 0.10) OVER (ORDER BY avg_heart_rate) AS p10
  FROM
    AvgHeartRatePerStay
)
SELECT
  avg_heart_rate,
  p10,
  p20,
  p30,
  p40,
  p50,
  p60,
  p70,
  p80,
  p90
FROM
  PercentileCalculation
WHERE
  avg_heart_rate = 110;