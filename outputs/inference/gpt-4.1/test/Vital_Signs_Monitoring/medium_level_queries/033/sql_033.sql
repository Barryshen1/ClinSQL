WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 62 AND 72
),

mean_hr AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220045 -- Heart Rate
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

hr_category AS (
  SELECT
    m.stay_id,
    m.mean_hr,
    CASE
      WHEN m.mean_hr < 60 THEN '<60'
      WHEN m.mean_hr >= 60 AND m.mean_hr < 100 THEN '60-99'
      WHEN m.mean_hr >= 100 AND m.mean_hr < 120 THEN '100-119'
      WHEN m.mean_hr >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_cat
  FROM
    mean_hr m
  WHERE
    m.mean_hr IS NOT NULL
),

acute_mi AS (
  SELECT
    c.stay_id,
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410')) OR
             (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21'))
        THEN 1 ELSE 0 END
    ) AS has_acute_mi
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  GROUP BY
    c.stay_id
)

SELECT
  h.hr_cat AS heart_rate_category,
  COUNT(h.stay_id) AS icu_stay_count,
  ROUND(100 * SUM(a.has_acute_mi) / COUNT(h.stay_id), 1) AS percent_with_acute_mi
FROM
  hr_category h
  LEFT JOIN acute_mi a
    ON h.stay_id = a.stay_id
WHERE
  h.hr_cat IS NOT NULL
GROUP BY
  h.hr_cat
ORDER BY
  CASE h.hr_cat
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;