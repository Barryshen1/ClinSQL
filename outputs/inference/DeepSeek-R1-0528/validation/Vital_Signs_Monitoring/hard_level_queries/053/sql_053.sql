WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age,
    MAX(CASE 
          WHEN d.icd_code IS NOT NULL THEN 1 
          ELSE 0 
        END) AS shock_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ie.hadm_id = d.hadm_id
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '7855%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'R57%')
    )
  WHERE p.gender = 'F'
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, p.anchor_age, p.anchor_year
  HAVING age BETWEEN 59 AND 69
),

hypotension_burden AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) / COUNT(*) AS hypotension_burden
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220052, 220181, 225312)  -- MAP items
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),

tachycardia_burden AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) / COUNT(*) AS tachycardia_burden
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220045, 211)  -- HR items
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),

shock_index_pairs AS (
  SELECT 
    hr.stay_id,
    hr.charttime AS hr_time,
    hr.valuenum AS hr_value,
    sbp.valuenum AS sbp_value,
    ABS(TIMESTAMP_DIFF(hr.charttime, sbp.charttime, MINUTE)) AS minute_diff
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` hr
    ON c.stay_id = hr.stay_id
    AND hr.itemid IN (220045, 211)  -- HR
    AND hr.valuenum IS NOT NULL
    AND hr.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` sbp
    ON c.stay_id = sbp.stay_id
    AND sbp.itemid IN (220179, 225309)  -- SBP
    AND sbp.valuenum IS NOT NULL
    AND sbp.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND sbp.charttime BETWEEN TIMESTAMP_SUB(hr.charttime, INTERVAL 30 MINUTE) 
                         AND TIMESTAMP_ADD(hr.charttime, INTERVAL 30 MINUTE)
),

best_shock_index AS (
  SELECT 
    stay_id,
    MAX(hr_value / NULLIF(sbp_value, 0)) AS composite_instability_score
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (
        PARTITION BY stay_id, hr_time 
        ORDER BY minute_diff
      ) AS rn
    FROM shock_index_pairs
  )
  WHERE rn = 1
  GROUP BY stay_id
),

outcomes AS (
  SELECT 
    c.stay_id,
    a.hospital_expire_flag AS mortality
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
),

combined AS (
  SELECT 
    c.stay_id,
    c.shock_group,
    hb.hypotension_burden,
    tb.tachycardia_burden,
    si.composite_instability_score,
    c.los,
    o.mortality
  FROM cohort c
  LEFT JOIN hypotension_burden hb ON c.stay_id = hb.stay_id
  LEFT JOIN tachycardia_burden tb ON c.stay_id = tb.stay_id
  LEFT JOIN best_shock_index si ON c.stay_id = si.stay_id
  LEFT JOIN outcomes o ON c.stay_id = o.stay_id
)

SELECT 
  shock_group,
  COUNT(*) AS num_patients,
  AVG(composite_instability_score) AS mean_composite,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(1)] AS p25_composite,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(2)] AS p50_composite,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(3)] AS p75_composite,
  
  AVG(hypotension_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 4)[OFFSET(1)] AS p25_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 4)[OFFSET(2)] AS p50_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 4)[OFFSET(3)] AS p75_hypotension_burden,
  
  AVG(tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 4)[OFFSET(1)] AS p25_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 4)[OFFSET(2)] AS p50_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 4)[OFFSET(3)] AS p75_tachycardia_burden,
  
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS p50_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
  
  AVG(mortality) AS mortality_rate
FROM combined
GROUP BY shock_group;