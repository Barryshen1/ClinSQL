WITH
-- Get male patients aged 78-88
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),

-- Identify HHS patients (glucose > 600 mg/dL)
hhs_patients AS (
  SELECT DISTINCT
    l.subject_id,
    l.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE
    d.label = 'Glucose'
    AND l.valuenum > 600
    AND l.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    hhs_patients h ON s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id
),

-- Get vital signs data for first 24 hours of each ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    d.label AS vital_sign,
    c.valuenum,
    c.valueuom
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    d.label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
),

-- Calculate CV for each vital sign per stay
vital_cv AS (
  SELECT
    stay_id,
    vital_sign,
    STDDEV(valuenum) / AVG(valuenum) AS cv
  FROM
    vital_signs
  GROUP BY
    stay_id, vital_sign
),

-- Sum CVs for each stay (now including subject_id and hadm_id)
stay_scores AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    v.stay_id,
    SUM(v.cv) AS instability_score
  FROM
    vital_cv v
  JOIN
    icu_stays i ON v.stay_id = i.stay_id
  GROUP BY
    i.subject_id, i.hadm_id, v.stay_id
),

-- Calculate quartiles for instability scores
quartiles AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS q75
  FROM
    stay_scores
  LIMIT 1
),

-- Get top quartile stays
top_quartile_stays AS (
  SELECT
    s.stay_id,
    s.instability_score,
    s.subject_id,
    s.hadm_id,
    i.icu_los_hours,
    a.hospital_expire_flag
  FROM
    stay_scores s
  JOIN
    icu_stays i ON s.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  CROSS JOIN
    quartiles q
  WHERE
    s.instability_score >= q.q75
),

-- Count abnormal vitals per stay
abnormal_vitals AS (
  SELECT
    stay_id,
    COUNT(DISTINCT
      CASE
        WHEN (vital_sign = 'Heart Rate' AND (valuenum < 60 OR valuenum > 100))
          OR (vital_sign = 'Mean Arterial Pressure' AND (valuenum < 65 OR valuenum > 110))
          OR (vital_sign = 'Respiratory Rate' AND (valuenum < 12 OR valuenum > 20))
        THEN vital_sign
      END
    ) AS abnormal_count
  FROM
    vital_signs
  GROUP BY
    stay_id
)

-- Final result
SELECT
  t.stay_id,
  t.instability_score,
  NTILE(10) OVER(ORDER BY t.instability_score) AS decile,
  a.abnormal_count,
  t.icu_los_hours,
  t.hospital_expire_flag AS in_hospital_mortality
FROM
  top_quartile_stays t
JOIN
  abnormal_vitals a ON t.stay_id = a.stay_id
ORDER BY
  t.instability_score DESC;