WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),

rr_first48 AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    cohort c
    ON ce.stay_id = c.stay_id
  WHERE
    LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    ce.stay_id
),

rr_categories AS (
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12–20'
      WHEN avg_rr > 20 AND avg_rr < 30 THEN '21–29'
      WHEN avg_rr >= 30 THEN '≥30'
    END AS rr_group
  FROM
    rr_first48
),

stroke_flag AS (
  SELECT DISTINCT
    icu.stay_id,
    TRUE AS has_stroke
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    (dx.icd_version = 9 AND dx.icd_code BETWEEN '430' AND '438')
    OR (dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^I6[0-9]'))
),

final_data AS (
  SELECT
    r.stay_id,
    r.rr_group,
    COALESCE(s.has_stroke, FALSE) AS has_stroke
  FROM
    rr_categories r
  LEFT JOIN
    stroke_flag s
    ON r.stay_id = s.stay_id
)

SELECT
  rr_group,
  COUNT(*) AS patient_count,
  SUM(CASE WHEN has_stroke THEN 1 ELSE 0 END) AS stroke_count,
  ROUND(SUM(CASE WHEN has_stroke THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS stroke_rate_percent
FROM
  final_data
GROUP BY
  rr_group
ORDER BY
  CASE rr_group
    WHEN '<12' THEN 1
    WHEN '12–20' THEN 2
    WHEN '21–29' THEN 3
    WHEN '≥30' THEN 4
  END;