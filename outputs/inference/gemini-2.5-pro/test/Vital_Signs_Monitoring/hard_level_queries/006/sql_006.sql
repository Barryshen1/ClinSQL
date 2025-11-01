WITH
-- Step 1: Identify the cohort of male ICU patients aged 60-70 with a UGIB diagnosis.
ugib_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE
        dx.hadm_id = i.hadm_id
        AND (
          -- Common UGIB ICD-9 codes
          dx.icd_code LIKE '578%'      -- Hemorrhage of gastrointestinal tract
          OR dx.icd_code LIKE '531.0%' -- Acute gastric ulcer with hemorrhage
          OR dx.icd_code LIKE '531.2%' -- Acute gastric ulcer with hemorrhage and perforation
          OR dx.icd_code LIKE '531.4%' -- Chronic gastric ulcer with hemorrhage
          OR dx.icd_code LIKE '532.0%' -- Acute duodenal ulcer with hemorrhage
          OR dx.icd_code LIKE '532.2%' -- Acute duodenal ulcer with hemorrhage and perforation
          OR dx.icd_code LIKE '532.4%' -- Chronic duodenal ulcer with hemorrhage
          -- Common UGIB ICD-10 codes
          OR dx.icd_code LIKE 'K92.0%' -- Hematemesis
          OR dx.icd_code LIKE 'K92.1%' -- Melena
          OR dx.icd_code LIKE 'K92.2%' -- Gastrointestinal hemorrhage, unspecified
          OR dx.icd_code LIKE 'K25.0%' -- Acute gastric ulcer with hemorrhage
          OR dx.icd_code LIKE 'K25.4%' -- Chronic or unspecified gastric ulcer with hemorrhage
          OR dx.icd_code LIKE 'K26.0%' -- Acute duodenal ulcer with hemorrhage
          OR dx.icd_code LIKE 'K26.4%' -- Chronic or unspecified duodenal ulcer with hemorrhage
        )
    )
),
-- Step 2: Extract relevant vital signs for the cohort during the first 48 hours of their ICU stay.
vitals_first_48h AS (
  SELECT
    cohort.stay_id,
    -- Heart Rate (itemid: 220045)
    CASE WHEN ce.itemid = 220045 THEN ce.valuenum END AS heart_rate,
    -- Mean Arterial Pressure (itemids: 220052, 220181 for NIBP, 225312 for invasive)
    CASE WHEN ce.itemid IN (220052, 220181, 225312) THEN ce.valuenum END AS map,
    -- Respiratory Rate (itemid: 220210)
    CASE WHEN ce.itemid = 220210 THEN ce.valuenum END AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    ugib_cohort AS cohort
    ON ce.stay_id = cohort.stay_id
  WHERE
    ce.charttime BETWEEN cohort.intime AND TIMESTAMP_ADD(cohort.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (
      220045, -- Heart Rate
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312, -- ART BP mean
      220210  -- Respiratory Rate
    )
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 -- Basic data cleaning
),
-- Step 3: For each stay, count the number of normal and abnormal vital signs.
instability_metrics_per_stay AS (
  SELECT
    stay_id,
    -- Tachycardia: HR > 100
    COUNTIF(heart_rate > 100) AS tachy_count,
    COUNT(heart_rate) AS hr_total_count,
    -- Hypotension: MAP < 65
    COUNTIF(map < 65) AS map_low_count,
    COUNT(map) AS map_total_count,
    -- Tachypnea: RR > 20
    COUNTIF(respiratory_rate > 20) AS rr_high_count,
    COUNT(respiratory_rate) AS rr_total_count
  FROM
    vitals_first_48h
  GROUP BY
    stay_id
),
-- Step 4: Calculate the instability index and other metrics for each stay, and rank into deciles.
cohort_with_metrics AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    -- Individual instability percentages
    SAFE_DIVIDE(im.tachy_count, im.hr_total_count) AS pct_tachycardia,
    SAFE_DIVIDE(im.map_low_count, im.map_total_count) AS pct_low_map,
    SAFE_DIVIDE(im.rr_high_count, im.rr_total_count) AS pct_tachypnea,
    -- Overall Vital Instability Index: (unstable measurements) / (total measurements)
    SAFE_DIVIDE(
      im.tachy_count + im.map_low_count + im.rr_high_count,
      im.hr_total_count + im.map_total_count + im.rr_total_count
    ) AS vital_instability_index,
    -- Rank patients by instability into 10 groups (deciles)
    NTILE(10) OVER(ORDER BY SAFE_DIVIDE(
      im.tachy_count + im.map_low_count + im.rr_high_count,
      im.hr_total_count + im.map_total_count + im.rr_total_count
    ) DESC) AS instability_decile
  FROM
    ugib_cohort AS c
  INNER JOIN
    instability_metrics_per_stay AS im
    ON c.stay_id = im.stay_id
  WHERE
    -- Ensure the patient has at least one relevant vital sign to be included
    (im.hr_total_count + im.map_total_count + im.rr_total_count) > 0
),
-- Step 5: Calculate the 95th percentile of the index for the entire cohort (to answer Part 1).
percentile_calc AS (
  SELECT
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS p95_vital_instability_index
  FROM
    cohort_with_metrics
)
-- Final Step: Group by decile to compare the top 10% vs. the other 90% (controls).
SELECT
  -- Answer to Part 1 of the question
  p.p95_vital_instability_index AS p95_vital_instability_index_all_patients,
  -- Answer to Part 2 of the question
  CASE
    WHEN c.instability_decile = 1 THEN 'Top Decile (Most Unstable)'
    ELSE 'Controls (Bottom 90%)'
  END AS patient_group,
  COUNT(DISTINCT c.stay_id) AS number_of_stays,
  AVG(c.vital_instability_index) AS avg_vital_instability_index,
  AVG(c.pct_tachycardia) AS avg_pct_time_tachycardic,
  AVG(c.pct_low_map) AS avg_pct_time_with_map_lt_65,
  AVG(c.pct_tachypnea) AS avg_pct_time_tachypneic,
  AVG(c.los) AS avg_icu_los_days,
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM
  cohort_with_metrics AS c
CROSS JOIN
  percentile_calc AS p
GROUP BY
  patient_group,
  p.p95_vital_instability_index
ORDER BY
  patient_group DESC;