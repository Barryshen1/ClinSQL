WITH female_60_70 AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
),

mixed_shock AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%shock%'
  GROUP BY
    d.subject_id,
    d.hadm_id
  HAVING
    COUNT(DISTINCT d.icd_code) >= 2
),

cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM
    female_60_70 AS f
    JOIN mixed_shock AS ms
      ON f.subject_id = ms.subject_id
      AND f.hadm_id = ms.hadm_id
),

map_hr_items AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
    OR LOWER(label) LIKE '%heart rate%'
),

instability_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    CASE
      WHEN LOWER(di.label) LIKE '%mean arterial pressure%' 
           AND ce.valuenum < 65 THEN 1
      ELSE 0
    END AS is_hypo,
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' 
           AND ce.valuenum > 100 THEN 1
      ELSE 0
    END AS is_tachy
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.subject_id = ce.subject_id
      AND c.hadm_id = ce.hadm_id
      AND c.stay_id = ce.stay_id
      AND ce.charttime BETWEEN c.intime 
                          AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    JOIN map_hr_items AS di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
),

instability_score AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(is_hypo + is_tachy) AS instability_score,
    MAX(is_hypo) AS had_hypotension,
    MAX(is_tachy) AS had_tachycardia
  FROM
    instability_events
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
),

score_percentiles AS (
  -- Alias the table as "s" so we can unambiguously refer to the column
  SELECT
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(95)] AS p95,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(90)] AS p90
  FROM
    instability_score AS s
),

with_flags AS (
  SELECT
    s.*,
    CASE 
      WHEN s.instability_score >= sp.p90 THEN 'top_decile' 
      ELSE 'cohort' 
    END AS group_flag
  FROM
    instability_score AS s
    CROSS JOIN score_percentiles AS sp
),

admissions_flag AS (
  SELECT
    hadm_id,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT
  wf.group_flag,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(wf.had_hypotension) / COUNT(*), 1) AS pct_with_hypotension,
  ROUND(100.0 * SUM(wf.had_tachycardia) / COUNT(*), 1) AS pct_with_tachycardia,
  -- median ICU LOS in hours per group (approximate)
  ROUND(
    APPROX_QUANTILES(c.los, 2)[OFFSET(1)]
    , 1
  ) AS median_icu_los_hours,
  ROUND(100.0 * SUM(a.hospital_expire_flag) / COUNT(*), 1) AS hospital_mortality_pct
FROM
  with_flags AS wf
  JOIN cohort AS c
    ON wf.subject_id = c.subject_id
    AND wf.stay_id = c.stay_id
  LEFT JOIN admissions_flag AS a
    ON wf.hadm_id = a.hadm_id
GROUP BY
  wf.group_flag
ORDER BY
  wf.group_flag DESC;