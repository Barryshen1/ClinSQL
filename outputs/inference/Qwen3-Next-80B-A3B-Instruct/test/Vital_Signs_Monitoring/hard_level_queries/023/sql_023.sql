WITH hfnc_patients AS (
  SELECT DISTINCT i.stay_id
  FROM physionet-data.mimiciv_3_1_icu.inputevents i
  JOIN physionet-data.mimiciv_3_1_icu.d_items d ON i.itemid = d.itemid
  JOIN physionet-data.mimiciv_3_1_icu.icustays icu ON i.stay_id = icu.stay_id
  WHERE d.label = 'High Flow Nasal Cannula'
    AND i.starttime >= icu.intime
    AND i.starttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),

tachy_hypo_burden AS (
  SELECT
    c.stay_id,
    SUM(
      CASE 
        WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 
          DATETIME_DIFF(
            LEAD(c.charttime) OVER (PARTITION BY c.stay_id ORDER BY c.charttime), 
            c.charttime, 
            SECOND
          ) / 3600.0
        ELSE 0 
      END
    ) AS tachycardia_hours,
    SUM(
      CASE 
        WHEN c.itemid = 220050 AND c.valuenum < 90 THEN 
          DATETIME_DIFF(
            LEAD(c.charttime) OVER (PARTITION BY c.stay_id ORDER BY c.charttime), 
            c.charttime, 
            SECOND
          ) / 3600.0
        ELSE 0 
      END
    ) AS hypotension_hours
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  WHERE c.itemid IN (220045, 220050)
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

cohort AS (
  SELECT
    icu.stay_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu_admission,
    CASE WHEN hfnc.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_hfnc,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    COALESCE(th.tachycardia_hours, 0) AS tachycardia_hours,
    COALESCE(th.hypotension_hours, 0) AS hypotension_hours,
    COALESCE(th.tachycardia_hours, 0) + COALESCE(th.hypotension_hours, 0) AS instability_burden_hours
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON icu.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm ON icu.hadm_id = adm.hadm_id
  LEFT JOIN hfnc_patients hfnc ON icu.stay_id = hfnc.stay_id
  LEFT JOIN tachy_hypo_burden th ON icu.stay_id = th.stay_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 55 AND 65
)

SELECT
  'HFNC' AS group_name,
  PERCENTILE_CONT(instability_burden_hours, 0.5) OVER () AS median_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.25) OVER () AS p25_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.75) OVER () AS p75_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.95) OVER () AS p95_instability,
  AVG(tachycardia_hours) AS avg_tachycardia_hours,
  AVG(hypotension_hours) AS avg_hypotension_hours,
  AVG(icu_los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort
WHERE has_hfnc = 1

UNION ALL

SELECT
  'Control' AS group_name,
  PERCENTILE_CONT(instability_burden_hours, 0.5) OVER () AS median_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.25) OVER () AS p25_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.75) OVER () AS p75_instability,
  PERCENTILE_CONT(instability_burden_hours, 0.95) OVER () AS p95_instability,
  AVG(tachycardia_hours) AS avg_tachycardia_hours,
  AVG(hypotension_hours) AS avg_hypotension_hours,
  AVG(icu_los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort
WHERE has_hfnc = 0;