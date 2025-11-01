WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_icu BETWEEN 55 AND 65
),
hfnc_stays AS (
  SELECT 
    stay_id,
    MIN(starttime) AS hfnc_starttime
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE 
    itemid = 226719 
    AND value = 4  -- Changed to numeric code for HFNC
  GROUP BY stay_id
),
cohort_with_hfnc AS (
  SELECT 
    fc.*,
    CASE 
      WHEN hfnc.stay_id IS NOT NULL 
        AND hfnc.hfnc_starttime <= DATETIME_ADD(fc.intime, INTERVAL 24 HOUR) 
        THEN 1 
      ELSE 0 
    END AS hfnc_group
  FROM filtered_cohort fc
  LEFT JOIN hfnc_stays hfnc
    ON fc.stay_id = hfnc.stay_id
),
chart_24h AS (
  SELECT 
    c.stay_id,
    MAX(CASE 
          WHEN ce.itemid IN (220045, 211) AND ce.valuenum > 100 THEN 1 
          ELSE 0 
        END) AS tachycardia_flag,
    MAX(CASE 
          WHEN ce.itemid IN (220179, 51) AND ce.valuenum < 90 THEN 1 
          ELSE 0 
        END) AS hypotension_flag,
    MAX(CASE 
          WHEN ce.itemid IN (220210, 618) AND ce.valuenum > 24 THEN 1 
          ELSE 0 
        END) AS tachypnea_flag,
    MAX(CASE 
          WHEN ce.itemid IN (220277, 646) AND ce.valuenum < 90 THEN 1 
          ELSE 0 
        END) AS hypoxemia_flag
  FROM cohort_with_hfnc c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 211, 220179, 51, 220210, 618, 220277, 646)
  GROUP BY c.stay_id
),
instab_scores AS (
  SELECT 
    stay_id,
    tachycardia_flag + hypotension_flag + tachypnea_flag + hypoxemia_flag AS instability_score
  FROM chart_24h
),
hr_burden AS (
  SELECT 
    c.stay_id,
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS tachycardia_burden
  FROM cohort_with_hfnc c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.outtime
    AND ce.itemid IN (220045, 211)
  GROUP BY c.stay_id
),
sbp_burden AS (
  SELECT 
    c.stay_id,
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.valuenum < 90 THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS hypotension_burden
  FROM cohort_with_hfnc c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.outtime
    AND ce.itemid IN (220179, 51)
  GROUP BY c.stay_id
),
final_data AS (
  SELECT 
    c.stay_id,
    c.hfnc_group,
    COALESCE(i.instability_score, 0) AS instability_score,
    h.tachycardia_burden,
    s.hypotension_burden,
    c.los,
    c.hospital_expire_flag
  FROM cohort_with_hfnc c
  LEFT JOIN instab_scores i ON c.stay_id = i.stay_id
  LEFT JOIN hr_burden h ON c.stay_id = h.stay_id
  LEFT JOIN sbp_burden s ON c.stay_id = s.stay_id
),
grouped AS (
  SELECT 
    hfnc_group,
    APPROX_QUANTILES(instability_score, 100) AS instab_q,
    APPROX_QUANTILES(tachycardia_burden, 100) AS tachy_q,
    APPROX_QUANTILES(hypotension_burden, 100) AS hypo_q,
    APPROX_QUANTILES(los, 100) AS los_q,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM final_data
  GROUP BY hfnc_group
)
SELECT 
  hfnc_group,
  instab_q[OFFSET(25)] AS instab_p25,
  instab_q[OFFSET(50)] AS instab_median,
  instab_q[OFFSET(75)] AS instab_p75,
  instab_q[OFFSET(95)] AS instab_p95,
  tachy_q[OFFSET(25)] AS tachy_burden_p25,
  tachy_q[OFFSET(50)] AS tachy_burden_median,
  tachy_q[OFFSET(75)] AS tachy_burden_p75,
  tachy_q[OFFSET(95)] AS tachy_burden_p95,
  hypo_q[OFFSET(25)] AS hypo_burden_p25,
  hypo_q[OFFSET(50)] AS hypo_burden_median,
  hypo_q[OFFSET(75)] AS hypo_burden_p75,
  hypo_q[OFFSET(95)] AS hypo_burden_p95,
  los_q[OFFSET(25)] AS los_p25,
  los_q[OFFSET(50)] AS los_median,
  los_q[OFFSET(75)] AS los_p75,
  los_q[OFFSET(95)] AS los_p95,
  mortality_rate
FROM grouped
ORDER BY hfnc_group;