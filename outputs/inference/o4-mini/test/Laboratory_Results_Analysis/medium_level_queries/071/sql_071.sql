WITH female_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),

first_troponin AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    fe.charttime,
    fe.valuenum,
    fe.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY fe.subject_id, fe.hadm_id
      ORDER BY fe.charttime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` fe
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON fe.itemid = li.itemid
  WHERE
    -- filter for Troponin T by lab label, since loinc_code is not present
    LOWER(li.label) LIKE '%troponin t%'
    AND fe.valuenum IS NOT NULL
),

initial_troponin AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.valuenum,
    ft.ref_range_upper,
    CASE
      WHEN ft.valuenum <= ft.ref_range_upper THEN 'Normal'
      WHEN ft.valuenum <= 2 * ft.ref_range_upper THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    first_troponin ft
  WHERE
    ft.rn = 1
),

cohort_with_troponin AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    fc.admittime,
    fc.dischtime,
    it.valuenum,
    it.ref_range_upper,
    it.troponin_category
  FROM
    female_cohort fc
    JOIN initial_troponin it
      ON fc.subject_id = it.subject_id
      AND fc.hadm_id = it.hadm_id
),

stats AS (
  SELECT
    troponin_category,
    COUNT(*) AS n_admissions,
    AVG(
      TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
    ) AS avg_los_days
  FROM
    cohort_with_troponin
  GROUP BY
    troponin_category
),

total_cohort AS (
  SELECT
    COUNT(*) AS total_n
  FROM
    cohort_with_troponin
)

SELECT
  s.troponin_category,
  s.n_admissions,
  ROUND(100.0 * s.n_admissions / t.total_n, 1) AS pct_of_cohort,
  ROUND(s.avg_los_days, 2) AS avg_los_days
FROM
  stats s
  CROSS JOIN total_cohort t
ORDER BY
  CASE s.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;