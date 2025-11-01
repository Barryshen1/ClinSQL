WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
),

hr_per_stay AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = c.subject_id
      AND ce.hadm_id    = c.hadm_id
      AND ce.stay_id    = c.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum BETWEEN 30 AND 300
  GROUP BY
    c.stay_id
),

hr_bucketed AS (
  SELECT
    stay_id,
    mean_hr,
    CASE
      WHEN mean_hr < 60 THEN '<60'
      WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119'
      ELSE '>=120'
    END AS hr_category
  FROM
    hr_per_stay
),

mi_flags AS (
  SELECT
    DISTINCT icu.stay_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = icu.hadm_id
          AND (
            (d.icd_version = 9  AND d.icd_code LIKE '410%')
            OR
            (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
          )
      ) THEN 1
      ELSE 0
    END AS acute_mi_flag
  FROM
    cohort icu
)

SELECT
  hb.hr_category,
  COUNT(*)                      AS total_stays,
  SUM(mf.acute_mi_flag)         AS mi_count,
  ROUND(SUM(mf.acute_mi_flag) / COUNT(*) * 100, 2) AS mi_percent
FROM
  hr_bucketed hb
  LEFT JOIN mi_flags mf
    USING (stay_id)
GROUP BY
  hb.hr_category
ORDER BY
  -- Preserve the natural order of categories
  CASE
    WHEN hb.hr_category = '<60'   THEN 1
    WHEN hb.hr_category = '60-99' THEN 2
    WHEN hb.hr_category = '100-119' THEN 3
    WHEN hb.hr_category = '>=120' THEN 4
  END;