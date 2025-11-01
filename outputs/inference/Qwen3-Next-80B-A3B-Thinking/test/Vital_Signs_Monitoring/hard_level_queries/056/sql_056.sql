WITH target_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),
combined_events AS (
  SELECT 
    c.stay_id,
    c.charttime,
    CASE 
      WHEN c.itemid = 223761 AND c.valuenum > 38.5 THEN 1
      WHEN c.itemid = 220277 AND c.valuenum < 90 THEN 1
      WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1
      ELSE 0
    END AS meets_any_condition
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN target_patients tp ON c.stay_id = tp.stay_id
  WHERE c.itemid IN (223761, 220277, 220210)
    AND c.charttime >= tp.intime 
    AND c.charttime <= tp.intime + INTERVAL '48' HOUR
    AND c.valuenum IS NOT NULL
),
combined_events_with_next AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.meets_any_condition,
    LEAD(c.charttime) OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS next_charttime,
    tp.intime + INTERVAL '48' HOUR AS end_48h
  FROM combined_events c
  JOIN target_patients tp ON c.stay_id = tp.stay_id
),
instability_hours AS (
  SELECT 
    stay_id,
    SUM(
      CASE 
        WHEN meets_any_condition = 1 THEN 
          COALESCE(
            TIMESTAMP_DIFF(next_charttime, charttime, HOUR),
            TIMESTAMP_DIFF(end_48h, charttime, HOUR)
          )
        ELSE 0
      END
    ) AS instability_hours
  FROM combined_events_with_next
  GROUP BY stay_id
),
temp_events AS (
  SELECT 
    c.stay_id,
    c.charttime,
    CASE WHEN c.valuenum > 38.5 THEN 1 ELSE 0 END AS meets_fever
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN target_patients tp ON c.stay_id = tp.stay_id
  WHERE c.itemid = 223761
    AND c.charttime >= tp.intime 
    AND c.charttime <= tp.intime + INTERVAL '48' HOUR
    AND c.valuenum IS NOT NULL
),
temp_events_with_next AS (
  SELECT 
    t.stay_id,
    t.charttime,
    t.meets_fever,
    LEAD(t.charttime) OVER (PARTITION BY t.stay_id ORDER BY t.charttime) AS next_charttime,
    tp.intime + INTERVAL '48' HOUR AS end_48h
  FROM temp_events t
  JOIN target_patients tp ON t.stay_id = tp.stay_id
),
fever_hours AS (
  SELECT 
    stay_id,
    SUM(
      CASE 
        WHEN meets_fever = 1 THEN 
          COALESCE(
            TIMESTAMP_DIFF(next_charttime, charttime, HOUR),
            TIMESTAMP_DIFF(end_48h, charttime, HOUR)
          )
        ELSE 0
      END
    ) AS fever_hours
  FROM temp_events_with_next
  GROUP BY stay_id
),
spo2_events AS (
  SELECT 
    c.stay_id,
    c.charttime,
    CASE WHEN c.valuenum < 90 THEN 1 ELSE 0 END AS meets_hypoxemia
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN target_patients tp ON c.stay_id = tp.stay_id
  WHERE c.itemid = 220277
    AND c.charttime >= tp.intime 
    AND c.charttime <= tp.intime + INTERVAL '48' HOUR
    AND c.valuenum IS NOT NULL
),
spo2_events_with_next AS (
  SELECT 
    s.stay_id,
    s.charttime,
    s.meets_hypoxemia,
    LEAD(s.charttime) OVER (PARTITION BY s.stay_id ORDER BY s.charttime) AS next_charttime,
    tp.intime + INTERVAL '48' HOUR AS end_48h
  FROM spo2_events s
  JOIN target_patients tp ON s.stay_id = tp.stay_id
),
hypoxemia_hours AS (
  SELECT 
    stay_id,
    SUM(
      CASE 
        WHEN meets_hypoxemia = 1 THEN 
          COALESCE(
            TIMESTAMP_DIFF(next_charttime, charttime, HOUR),
            TIMESTAMP_DIFF(end_48h, charttime, HOUR)
          )
        ELSE 0
      END
    ) AS hypoxemia_hours
  FROM spo2_events_with_next
  GROUP BY stay_id
),
rr_events AS (
  SELECT 
    c.stay_id,
    c.charttime,
    CASE WHEN c.valuenum > 20 THEN 1 ELSE 0 END AS meets_tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN target_patients tp ON c.stay_id = tp.stay_id
  WHERE c.itemid = 220210
    AND c.charttime >= tp.intime 
    AND c.charttime <= tp.intime + INTERVAL '48' HOUR
    AND c.valuenum IS NOT NULL
),
rr_events_with_next AS (
  SELECT 
    r.stay_id,
    r.charttime,
    r.meets_tachypnea,
    LEAD(r.charttime) OVER (PARTITION BY r.stay_id ORDER BY r.charttime) AS next_charttime,
    tp.intime + INTERVAL '48' HOUR AS end_48h
  FROM rr_events r
  JOIN target_patients tp ON r.stay_id = tp.stay_id
),
tachypnea_hours AS (
  SELECT 
    stay_id,
    SUM(
      CASE 
        WHEN meets_tachypnea = 1 THEN 
          COALESCE(
            TIMESTAMP_DIFF(next_charttime, charttime, HOUR),
            TIMESTAMP_DIFF(end_48h, charttime, HOUR)
          )
        ELSE 0
      END
    ) AS tachypnea_hours
  FROM rr_events_with_next
  GROUP BY stay_id
),
all_hours AS (
  SELECT 
    tp.stay_id,
    tp.los,
    tp.hospital_expire_flag,
    ih.instability_hours,
    fh.fever_hours,
    hh.hypoxemia_hours,
    th.tachypnea_hours
  FROM target_patients tp
  LEFT JOIN instability_hours ih ON tp.stay_id = ih.stay_id
  LEFT JOIN fever_hours fh ON tp.stay_id = fh.stay_id
  LEFT JOIN hypoxemia_hours hh ON tp.stay_id = hh.stay_id
  LEFT JOIN tachypnea_hours th ON tp.stay_id = th.stay_id
),
percentile_90 AS (
  SELECT 
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_hours) AS p90
  FROM all_hours
  WHERE instability_hours IS NOT NULL
)

SELECT 
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(fever_hours) AS mean_fever_hours,
  AVG(hypoxemia_hours) AS mean_hypoxemia_hours,
  AVG(tachypnea_hours) AS mean_tachypnea_hours
FROM all_hours
CROSS JOIN percentile_90
WHERE all_hours.instability_hours >= percentile_90.p90;