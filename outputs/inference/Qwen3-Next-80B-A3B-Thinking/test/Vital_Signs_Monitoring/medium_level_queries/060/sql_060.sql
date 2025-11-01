WITH cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),
sbp_max AS (
  SELECT
    c.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220050
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),
stroke AS (
  SELECT
    c.hadm_id,
    MAX(CASE
      WHEN d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438' THEN 1
      WHEN d.icd_version = 10 AND d.icd_code >= 'I60' AND d.icd_code <= 'I69' THEN 1
      ELSE 0
    END) AS has_stroke
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY
    c.hadm_id
),
combined AS (
  SELECT
    s.stay_id,
    s.max_sbp,
    st.has_stroke
  FROM
    sbp_max s
  JOIN
    cohort c
    ON s.stay_id = c.stay_id
  LEFT JOIN
    stroke st
    ON c.hadm_id = st.hadm_id
)
SELECT
  CASE
    WHEN max_sbp < 130 THEN '<130'
    WHEN max_sbp BETWEEN 130 AND 139 THEN '130-139'
    WHEN max_sbp BETWEEN 140 AND 159 THEN '140-159'
    ELSE '≥160'
  END AS sbp_category,
  COUNT(*) AS total_patients,
  SUM(has_stroke) AS stroke_count,
  ROUND(SUM(has_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM
  combined
WHERE
  max_sbp IS NOT NULL
GROUP BY
  sbp_category
ORDER BY
  sbp_category;