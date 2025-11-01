WITH first_stays AS (
  SELECT 
    s.subject_id, s.stay_id, s.hadm_id, s.intime, s.los,
    p.gender, p.anchor_age, p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- Fixed: gender is STRING ('M' = male)
    AND p.anchor_age BETWEEN 68 AND 78
),
trauma_adms AS (
  SELECT 
    d.subject_id, d.hadm_id,
    COUNT(CASE WHEN d.icd_version = 'ICD-10-CM' AND d.icd_code LIKE 'S%' THEN 1 END) AS trauma_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
  HAVING trauma_count >= 2
),
eligible_stays AS (
  SELECT f.*
  FROM first_stays f
  INNER JOIN trauma_adms t ON f.hadm_id = t.hadm_id
  WHERE f.rn = 1
),
vitals AS (
  SELECT 
    e.subject_id, e.stay_id, e.hadm_id, e.intime,
    c.charttime, c.itemid, c.valuenum
  FROM eligible_stays e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON e.stay_id = c.stay_id
  WHERE c.charttime >= e.intime 
    AND c.charttime < TIMESTAMP_ADD(e.intime, INTERVAL 1 DAY)
    AND c.valuenum IS NOT NULL
    AND (
      -- Heart Rate: 220045
      (c.itemid = 220045 AND c.valuenum BETWEEN 30 AND 250)
      OR
      -- Systolic BP: 220179 (manual), 300/443 (NIBP)
      (c.itemid IN (220179, 300, 443) AND c.valuenum BETWEEN 50 AND 250)
      OR
      -- Diastolic BP: 220180 (manual), 304/444 (NIBP)
      (c.itemid IN (220180, 304, 444) AND c.valuenum BETWEEN 30 AND 150)
      OR
      -- Respiratory Rate: 220210
      (c.itemid = 220210 AND c.valuenum BETWEEN 5 AND 60)
    )
),
vital_types AS (
  SELECT 
    subject_id, stay_id, hadm_id,
    CASE 
      WHEN itemid = 220045 THEN 'HR'
      WHEN itemid IN (220179, 300, 443) THEN 'SBP'
      WHEN itemid IN (220180, 304, 444) THEN 'DBP'
      WHEN itemid = 220210 THEN 'RR'
    END AS vital_type,
    valuenum, charttime
  FROM vitals
),
instability_scores AS (
  SELECT 
    subject_id, stay_id, hadm_id, intime, los,
    -- HR instability: SD if >10
    COALESCE(STDDEV_SAMP(CASE WHEN vital_type = 'HR' THEN valuenum END), 0) AS hr_sd,
    -- SBP instability: SD if >15
    COALESCE(STDDEV_SAMP(CASE WHEN vital_type = 'SBP' THEN valuenum END), 0) AS sbp_sd,
    -- DBP instability: SD if >10
    COALESCE(STDDEV_SAMP(CASE WHEN vital_type = 'DBP' THEN valuenum END), 0) AS dbp_sd,
    -- RR instability: SD if >5
    COALESCE(STDDEV_SAMP(CASE WHEN vital_type = 'RR' THEN valuenum END), 0) AS rr_sd
  FROM vital_types
  GROUP BY subject_id, stay_id, hadm_id, intime, los
  HAVING COUNT(*) >= 3  -- At least 3 total vitals for meaningful SD
),
scores AS (
  SELECT 
    *,
    -- Total instability score (full SD only if exceeds threshold)
    (CASE WHEN hr_sd > 10 THEN hr_sd ELSE 0 END) +
    (CASE WHEN sbp_sd > 15 THEN sbp_sd ELSE 0 END) +
    (CASE WHEN dbp_sd > 10 THEN dbp_sd ELSE 0 END) +
    (CASE WHEN rr_sd > 5 THEN rr_sd ELSE 0 END) AS instability_score
  FROM instability_scores
),
mortality AS (
  SELECT 
    s.subject_id, s.stay_id, s.hadm_id, s.intime, s.los, s.instability_score,
    a.hospital_expire_flag AS died_in_hosp
  FROM scores s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
),
base_stats AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM mortality
  WHERE instability_score > 0  -- Exclude no-vitals cases
),
quartile_stats AS (
  SELECT 
    quartile,
    COUNT(*) AS count,
    AVG(instability_score) AS mean_score,
    AVG(los) AS mean_los,
    AVG(died_in_hosp) AS mean_mortality
  FROM base_stats
  GROUP BY quartile
),
top_decile_episodes AS (
  SELECT 
    m.subject_id, m.stay_id,
    -- Group abnormal readings into episodes (within 5 min)
    COUNT(DISTINCT 
      CASE 
        WHEN vt.vital_type = 'HR' AND vt.valuenum > 100 
        THEN TIMESTAMP_TRUNC(
          TIMESTAMP_DIFF(vt.charttime, m.intime, MINUTE) / 5 * 5 * INTERVAL 1 MINUTE + m.intime, 
          MINUTE
        )
        END
    ) AS tachycardia_episodes,
    COUNT(DISTINCT 
      CASE 
        WHEN vt.vital_type = 'SBP' AND vt.valuenum < 90 
        THEN TIMESTAMP_TRUNC(
          TIMESTAMP_DIFF(vt.charttime, m.intime, MINUTE) / 5 * 5 * INTERVAL 1 MINUTE + m.intime, 
          MINUTE
        )
        END
    ) AS hypotension_episodes,
    COUNT(DISTINCT 
      CASE 
        WHEN vt.vital_type = 'RR' AND vt.valuenum > 20 
        THEN TIMESTAMP_TRUNC(
          TIMESTAMP_DIFF(vt.charttime, m.intime, MINUTE) / 5 * 5 * INTERVAL 1 MINUTE + m.intime, 
          MINUTE
        )
        END
    ) AS tachypnea_episodes
  FROM base_stats m
  INNER JOIN vital_types vt ON m.subject_id = vt.subject_id AND m.stay_id = vt.stay_id
  WHERE m.decile = 1
  GROUP BY m.subject_id, m.stay_id
),
top_decile_stats AS (
  SELECT 
    'Top Decile' AS group_label,
    COUNT(*) AS count,
    AVG(m.instability_score) AS mean_score,
    AVG(m.los) AS mean_los,
    AVG(m.died_in_hosp) AS mean_mortality,
    AVG(t.tachycardia_episodes) AS mean_tachycardia,
    AVG(t.hypotension_episodes) AS mean_hypotension,
    AVG(t.tachypnea_episodes) AS mean_tachypnea
  FROM base_stats m
  LEFT JOIN top_decile_episodes t ON m.subject_id = t.subject_id AND m.stay_id = t.stay_id
  WHERE m.decile = 1
)
SELECT 
  'Quartile 1 (Highest Instability)' AS stratum, count, ROUND(mean_score, 2) AS mean_score, 
  ROUND(mean_los, 2) AS mean_los, ROUND(mean_mortality, 3) AS mean_mortality,
  NULL AS mean_tachycardia, NULL AS mean_hypotension, NULL AS mean_tachypnea
FROM quartile_stats 
WHERE quartile = 1
UNION ALL
SELECT 
  'Quartile 2' AS stratum, count, ROUND(mean_score, 2), ROUND(mean_los, 2), ROUND(mean_mortality, 3),
  NULL, NULL, NULL
FROM quartile_stats 
WHERE quartile = 2
UNION ALL
SELECT 
  'Quartile 3' AS stratum, count, ROUND(mean_score, 2), ROUND(mean_los, 2), ROUND(mean_mortality, 3),
  NULL, NULL, NULL
FROM quartile_stats 
WHERE quartile = 3
UNION ALL
SELECT 
  'Quartile 4 (Lowest Instability)' AS stratum, count, ROUND(mean_score, 2), ROUND(mean_los, 2), ROUND(mean_mortality, 3),
  NULL, NULL, NULL
FROM quartile_stats 
WHERE quartile = 4
UNION ALL
SELECT 
  group_label AS stratum, count, ROUND(mean_score, 2), ROUND(mean_los, 2), ROUND(mean_mortality, 3),
  ROUND(mean_tachycardia, 2), ROUND(mean_hypotension, 2), ROUND(mean_tachypnea, 2)
FROM top_decile_stats
ORDER BY 
  CASE stratum 
    WHEN 'Quartile 1 (Highest Instability)' THEN 1
    WHEN 'Quartile 2' THEN 2
    WHEN 'Quartile 3' THEN 3
    WHEN 'Quartile 4 (Lowest Instability)' THEN 4
    WHEN 'Top Decile' THEN 5
  END;