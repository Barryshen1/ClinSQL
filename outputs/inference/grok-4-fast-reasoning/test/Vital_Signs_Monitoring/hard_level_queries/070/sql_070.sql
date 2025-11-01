WITH qualifying_stays AS (
  -- Cohort: male, 78-88yo, ICU stays with HHS diagnosis
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.los,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_code LIKE '250.2%'
    AND d.icd_version = 9
),
vital_readings AS (
  -- All relevant vital readings in first 24h for qualifying stays
  SELECT
    c.stay_id,
    c.valuenum,
    c.itemid,
    CASE c.itemid
      WHEN 220045 THEN 'HR'
      WHEN 220052 THEN 'MAP'
      WHEN 220181 THEN 'MAP'
      WHEN 220210 THEN 'RR'
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN qualifying_stays qs
    ON c.stay_id = qs.stay_id
  WHERE c.itemid IN (220045, 220052, 220181, 220210)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime >= qs.intime
    AND c.charttime <= TIMESTAMP_ADD(qs.intime, INTERVAL 1 DAY)
),
instability_calc AS (
  -- CV per vital per stay
  SELECT
    stay_id,
    vital,
    STDDEV(valuenum) / NULLIF(AVG(valuenum), 0) AS cv
  FROM vital_readings
  GROUP BY stay_id, vital
),
instability AS (
  -- Sum CVs per stay (instability score); join to qualifying_stays
  SELECT
    qs.stay_id,
    qs.subject_id,
    qs.hadm_id,
    qs.los,
    qs.intime,
    qs.outtime,
    qs.gender,
    qs.anchor_age,
    qs.hospital_expire_flag,
    COALESCE(SUM(ic.cv), 0) AS instability_score
  FROM qualifying_stays qs
  LEFT JOIN instability_calc ic
    ON qs.stay_id = ic.stay_id
  GROUP BY
    qs.stay_id, qs.subject_id, qs.hadm_id, qs.los, qs.intime, qs.outtime,
    qs.gender, qs.anchor_age, qs.hospital_expire_flag
),
cohort_with_decile AS (
  -- Add decile rank over full cohort (descending instability)
  SELECT *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM instability
),
q75_cte AS (
  -- 75th percentile for top quartile
  SELECT PERCENTILE_CONT(instability_score, 0.75) OVER () AS q75
  FROM cohort_with_decile
),
abnormal_stays AS (
  -- Rows with at least one abnormal reading per vital per stay
  SELECT
    c.stay_id,
    CASE c.itemid
      WHEN 220045 THEN 'HR'
      WHEN 220052 THEN 'MAP'
      WHEN 220181 THEN 'MAP'
      WHEN 220210 THEN 'RR'
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN qualifying_stays qs
    ON c.stay_id = qs.stay_id
  WHERE c.itemid IN (220045, 220052, 220181, 220210)
    AND c.valuenum IS NOT NULL
    AND c.charttime >= qs.intime
    AND c.charttime <= TIMESTAMP_ADD(qs.intime, INTERVAL 1 DAY)
    AND (
      (c.itemid = 220045 AND (c.valuenum < 60 OR c.valuenum > 100))
      OR (c.itemid IN (220052, 220181) AND (c.valuenum < 65 OR c.valuenum > 110))
      OR (c.itemid = 220210 AND (c.valuenum < 12 OR c.valuenum > 24))
    )
),
abnormal_count AS (
  -- Count distinct abnormal vitals per stay (0-3)
  SELECT
    stay_id,
    COUNT(DISTINCT vital) AS abnormal_vital_count
  FROM abnormal_stays
  GROUP BY stay_id
)
-- Final: top quartile stays with all metrics
SELECT
  cwd.stay_id,
  cwd.instability_score AS stay_instability_score,
  cwd.decile,
  COALESCE(ac.abnormal_vital_count, 0) AS abnormal_vital_count,
  cwd.los AS icu_los,
  cwd.hospital_expire_flag AS in_hospital_mortality
FROM cohort_with_decile cwd
CROSS JOIN q75_cte q
LEFT JOIN abnormal_count ac
  ON cwd.stay_id = ac.stay_id
WHERE cwd.instability_score >= q.q75
ORDER BY cwd.instability_score DESC;