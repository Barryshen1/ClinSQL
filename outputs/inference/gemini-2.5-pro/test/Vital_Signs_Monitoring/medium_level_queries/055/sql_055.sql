WITH PerStayAverages AS (
  -- First, calculate the average SpO2 in the first 24 hours for each relevant ICU stay
  SELECT
    i.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON i.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for the patient cohort: female, aged 87-97 at ICU admission
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 87 AND 97

    -- 2. Filter for SpO2 measurements from chartevents
    AND ce.itemid IN (
      220277, -- O2 saturation pulseoxymetry
      646     -- SpO2
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum <= 100 -- Sanity check for SpO2 values

    -- 3. Filter for measurements within the first 24 hours of the ICU stay
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY
    i.stay_id
)
-- Second, calculate the percentile of an 88% average SpO2 within the distribution of all per-stay averages
SELECT
  (COUNTIF(avg_spo2 <= 88) / COUNT(stay_id)) * 100 AS percentile_of_88_spo2
FROM
  PerStayAverages;