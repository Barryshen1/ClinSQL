WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
      ON di.icd_code = dic.icd_code
      AND di.icd_version = dic.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dic.long_title) LIKE '%hyperosmolar%'
),
vitals AS (
  SELECT
    c.stay_id,
    ce.itemid,
    di.label,
    di.lownormalvalue,
    di.highnormalvalue,
    ce.valuenum,
    CASE
      WHEN ce.valuenum < di.lownormalvalue
        OR ce.valuenum > di.highnormalvalue
      THEN 1 ELSE 0 END AS is_abnormal
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
      AND c.hadm_id    = ce.hadm_id
      AND c.stay_id   = ce.stay_id
      AND ce.charttime BETWEEN c.intime
                         AND TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.itemid IN (220045, 220179, 220210)  -- HR, MAP, RR
),
cv_per_vital AS (
  -- Compute CV (stddev/mean) for each vital sign per stay
  SELECT
    stay_id,
    label,
    STDDEV(valuenum) / AVG(valuenum) AS cv
  FROM vitals
  GROUP BY stay_id, label
),
abnormal_count AS (
  -- Count total abnormal readings per stay
  SELECT
    stay_id,
    SUM(is_abnormal) AS abnormal_vital_count
  FROM vitals
  GROUP BY stay_id
),
cv_metrics AS (
  -- Sum the three CVs and join abnormal counts
  SELECT
    v.stay_id,
    SUM(v.cv) AS instability_score,
    ac.abnormal_vital_count
  FROM cv_per_vital v
  JOIN abnormal_count ac
    USING (stay_id)
  GROUP BY v.stay_id, ac.abnormal_vital_count
),
p75_val AS (
  -- Compute the 75th percentile of instability_score
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
  FROM cv_metrics
),
ranked AS (
  SELECT
    m.stay_id,
    m.instability_score,
    NTILE(10) OVER (ORDER BY m.instability_score) AS decile,
    m.abnormal_vital_count,
    c.los,
    c.hospital_expire_flag,
    p.p75
  FROM
    cv_metrics m
    JOIN cohort c USING (stay_id)
    CROSS JOIN p75_val p
)
SELECT
  stay_id,
  instability_score,
  decile,
  abnormal_vital_count,
  los AS icu_los,
  hospital_expire_flag AS in_hospital_mortality
FROM
  ranked
WHERE
  instability_score >= p75
ORDER BY
  instability_score DESC;