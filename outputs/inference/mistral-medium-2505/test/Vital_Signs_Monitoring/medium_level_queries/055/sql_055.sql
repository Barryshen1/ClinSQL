WITH female_icu_stays AS (
  -- Get female ICU stays for patients aged 87-97
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),

spo2_measurements AS (
  -- Get SpO2 measurements (itemid 220277) within the first 24 hours of each ICU stay
  SELECT
    s.stay_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM
    female_icu_stays s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    s.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220277  -- SpO2 itemid (verify in d_items)
    AND ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
),

stay_avg_spo2 AS (
  -- Calculate average SpO2 per stay
  SELECT
    stay_id,
    AVG(spo2_value) AS avg_spo2
  FROM
    spo2_measurements
  GROUP BY
    stay_id
)

-- Calculate the percentile of 88% in the distribution of per-stay averages
SELECT
  PERCENT_RANK() OVER (ORDER BY avg_spo2) AS percentile,
  avg_spo2
FROM
  stay_avg_spo2
WHERE
  avg_spo2 IS NOT NULL
ORDER BY
  avg_spo2;