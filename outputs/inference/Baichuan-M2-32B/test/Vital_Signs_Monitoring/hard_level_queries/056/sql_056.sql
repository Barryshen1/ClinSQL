WITH
  -- Step 1: Identify eligible ICU stays for male patients aged 74-84
  eligible_icustays AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los,
      p.anchor_age,
      p.gender,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 74 AND 84
  ),
  -- Step 2: Get vital sign itemids from d_items (using known common itemids for MIMIC-IV)
  vital_itemids AS (
    SELECT 223762 AS itemid, 'Temperature' AS label, 'C' AS unitname  -- Temperature (C)
    UNION ALL
    SELECT 220210, 'SpO2', '%'  -- SpO2
    UNION ALL
    SELECT 220045, 'Respiratory Rate', 'per minute'  -- Respiratory Rate
  ),
  -- Step 3: Generate hourly bins for the first 48 hours of each ICU stay
  hourly_bins AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      TIMESTAMP_ADD(intime, INTERVAL hour HOUR) AS hour_start,
      TIMESTAMP_ADD(intime, INTERVAL hour + 1 HOUR) AS hour_end
    FROM
      eligible_icustays,
      UNNEST(GENERATE_ARRAY(0, 47)) AS hour
  ),
  -- Step 4: Filter chartevents to first 48 hours and relevant itemids
  chartevents_filtered AS (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.itemid,
      ce.valuenum,
      ce.valueuom
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
      vital_itemids vi
      ON ce.itemid = vi.itemid
    WHERE
      EXISTS (
        SELECT 1
        FROM eligible_icustays e
        WHERE
          ce.subject_id = e.subject_id
          AND ce.hadm_id = e.hadm_id
          AND ce.stay_id = e.stay_id
          AND ce.charttime BETWEEN e.intime AND TIMESTAMP_ADD(e.intime, INTERVAL 48 HOUR)
      )
  ),
  -- Step 5: Flag instability conditions per hour
  hourly_flags AS (
    SELECT
      hb.subject_id,
      hb.hadm_id,
      hb.stay_id,
      hb.hour_start,
      hb.hour_end,
      MAX(CASE WHEN vi.label = 'Temperature' AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS has_fever,
      MAX(CASE WHEN vi.label = 'SpO2' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypoxemia,
      MAX(CASE WHEN vi.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea
    FROM
      hourly_bins hb
    LEFT JOIN
      chartevents_filtered ce
      ON hb.subject_id = ce.subject_id
      AND hb.hadm_id = ce.hadm_id
      AND hb.stay_id = ce.stay_id
      AND ce.charttime BETWEEN hb.hour_start AND hb.hour_end
    LEFT JOIN
      vital_itemids vi
      ON ce.itemid = vi.itemid
    GROUP BY
      hb.subject_id, hb.hadm_id, hb.stay_id, hb.hour_start, hb.hour_end
  ),
  -- Step 6: Aggregate hourly flags to ICU stay level
  stay_metrics AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      COUNT(CASE WHEN has_fever = 1 OR has_hypoxemia = 1 OR has_tachypnea = 1 THEN 1 END) AS instability_hours,
      COUNT(CASE WHEN has_fever = 1 THEN 1 END) AS hours_fever,
      COUNT(CASE WHEN has_hypoxemia = 1 THEN 1 END) AS hours_hypoxemia,
      COUNT(CASE WHEN has_tachypnea = 1 THEN 1 END) AS hours_tachypnea
    FROM
      hourly_flags
    GROUP BY
      subject_id, hadm_id, stay_id
  ),
  -- Step 7: Join metrics with ICU stay details and compute 90th percentile
  stay_metrics_with_demographics AS (
    SELECT
      emi.subject_id,
      emi.hadm_id,
      emi.stay_id,
      emi.los,
      emi.hospital_expire_flag,
      sm.instability_hours,
      sm.hours_fever,
      sm.hours_hypoxemia,
      sm.hours_tachypnea
    FROM
      eligible_icustays emi
    INNER JOIN
      stay_metrics sm
      ON emi.subject_id = sm.subject_id
      AND emi.hadm_id = sm.hadm_id
      AND emi.stay_id = sm.stay_id
  ),
  instability_percentile AS (
    SELECT
      APPROX_QUANTILES(instability_hours, 100)[OFFSET(90)] AS p90_instability
    FROM
      stay_metrics_with_demographics
  ),
  -- Step 8: Identify top decile stays (instability_hours >= 90th percentile)
  top_decile_stays AS (
    SELECT
      smw.*
    FROM
      stay_metrics_with_demographics smw,
      instability_percentile p
    WHERE
      smw.instability_hours >= p.p90_instability
  )
-- Step 9: Compute final metrics for top decile
SELECT
  COUNT(*) AS n,
  AVG(los / 24.0) AS mean_icu_los_days,  -- Convert hours to days
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(hours_fever) AS mean_hours_fever,
  AVG(hours_hypoxemia) AS mean_hours_hypoxemia,
  AVG(hours_tachypnea) AS mean_hours_tachypnea
FROM
  top_decile_stays;