WITH
  -- 1) Identify each admission's first ICU stay for male patients aged 68-78
  first_icu_stays AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
    WHERE LOWER(p.gender) = 'male'
      AND p.anchor_age BETWEEN 68 AND 78
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
  ),
  -- 2) Trauma admissions (ICU stays associated with trauma/injury)
  trauma_admissions AS (
    SELECT
      fi.subject_id,
      fi.hadm_id,
      fi.stay_id,
      fi.intime,
      fi.outtime,
      fi.los
    FROM first_icu_stays AS fi
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.subject_id = fi.subject_id
     AND di.hadm_id = fi.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%trauma%'
       OR LOWER(dd.long_title) LIKE '%injury%'
       OR LOWER(dd.long_title) LIKE '%traumatic%'
  ),
  -- 3) 24-hour vitals within the first 24 hours of ICU intime
  vitals_24h AS (
    SELECT
      ta.subject_id,
      ta.hadm_id,
      ta.stay_id,
      ta.intime,
      ta.los,
      SUM(CASE
            WHEN LOWER(di.label) LIKE '%heart rate%' 
                 AND c.valuenum > 100
                 AND c.charttime BETWEEN ta.intime AND TIMESTAMP_ADD(ta.intime, INTERVAL 24 HOUR)
            THEN 1 ELSE 0
          END) AS hr_tachy,
      SUM(CASE
            WHEN (LOWER(di.label) LIKE '%systolic blood pressure%' OR LOWER(di.label) LIKE '%blood pressure%')
                 AND c.valuenum < 90
                 AND c.charttime BETWEEN ta.intime AND TIMESTAMP_ADD(ta.intime, INTERVAL 24 HOUR)
            THEN 1 ELSE 0
          END) AS sbp_hypot,
      SUM(CASE
            WHEN LOWER(di.label) LIKE '%respiratory rate%'
                 AND c.valuenum > 20
                 AND c.charttime BETWEEN ta.intime AND TIMESTAMP_ADD(ta.intime, INTERVAL 24 HOUR)
            THEN 1 ELSE 0
          END) AS rr_tachyp
    FROM trauma_admissions ta
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
      ON c.subject_id = ta.subject_id
     AND c.hadm_id = ta.hadm_id
     AND c.stay_id = ta.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON c.itemid = di.itemid
    WHERE c.charttime BETWEEN ta.intime AND TIMESTAMP_ADD(ta.intime, INTERVAL 24 HOUR)
      AND c.valuenum IS NOT NULL
    GROUP BY ta.subject_id, ta.hadm_id, ta.stay_id, ta.intime, ta.los
  ),
  -- 4) Attach mortality flag from admissions
  stay_with_mortality AS (
    SELECT
      v.subject_id,
      v.hadm_id,
      v.stay_id,
      v.intime,
      v.los,
      v.hr_tachy,
      v.sbp_hypot,
      v.rr_tachyp,
      (v.hr_tachy + v.sbp_hypot + v.rr_tachyp) AS instability_score,
      a.hospital_expire_flag
    FROM vitals_24h AS v
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON v.hadm_id = a.hadm_id
  ),
  -- 5) Quartile assignment
  stay_with_quartile AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
    FROM stay_with_mortality
  ),
  totals AS (
    SELECT COUNT(*) AS total FROM stay_with_mortality
  ),
  -- 6) Top decile (top 10% by instability_score)
  top_decile AS (
    SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.los,
           s.hr_tachy, s.sbp_hypot, s.rr_tachyp, s.instability_score
    FROM stay_with_mortality s
    CROSS JOIN totals t
    QUALIFY ROW_NUMBER() OVER (ORDER BY s.instability_score DESC) <= CEIL(0.10 * t.total)
  )

-- Part 1: Quartile statistics
SELECT
  CAST(q.quartile AS STRING) AS quartile_group,
  COUNT(*) AS n_stays,
  AVG(q.instability_score) AS mean_score,
  AVG(q.los) AS mean_icu_los,
  AVG(CAST(q.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM stay_with_quartile q
GROUP BY quartile
UNION ALL
-- Part 2: Top decile metrics
SELECT
  'top_decile' AS quartile_group,
  NULL AS n_stays,
  NULL AS mean_score,
  NULL AS mean_icu_los,
  NULL AS mortality_rate,
  AVG(t.hr_tachy) AS mean_tachycardia_episodes,
  AVG(t.sbp_hypot) AS mean_hypotension_episodes,
  AVG(t.rr_tachyp) AS mean_tachypnea_episodes
FROM top_decile t
ORDER BY quartile_group;