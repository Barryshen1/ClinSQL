WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    -- Calculate age at ICU admission
    pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    -- Filter for age 87-97 at ICU admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) 
        BETWEEN 87 AND 97
),

spo2_aggregated AS (
  SELECT 
    c.stay_id,
    AVG(ch.valuenum) AS avg_spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON c.stay_id = ch.stay_id
  WHERE 
    ch.itemid IN (220277, 223761)  -- SpO2 item_ids
    AND ch.valuenum IS NOT NULL
    -- First 24 hours of ICU stay
    AND ch.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
)

-- Calculate percentile for 88%
SELECT 
  (COUNTIF(avg_spo2 <= 88) * 100.0) / COUNT(*) AS percentile
FROM spo2_aggregated;