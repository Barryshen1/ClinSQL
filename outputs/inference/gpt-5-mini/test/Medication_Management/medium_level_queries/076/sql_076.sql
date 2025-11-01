WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND SAFE_CAST(di.icd_version AS STRING) = SAFE_CAST(dd.icd_version AS STRING)
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND SAFE_CAST(di.icd_version AS STRING) = SAFE_CAST(dd.icd_version AS STRING)
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND (
          LOWER(dd.long_title) LIKE '%acute%'
          OR LOWER(dd.long_title) LIKE '%decomp%'
        )
    )
),

meds AS (
  -- prescriptions
  SELECT
    c.hadm_id,
    p.starttime AS starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c USING(hadm_id)
  WHERE
    p.starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide)')
    AND p.starttime BETWEEN c.admittime AND c.dischtime

  UNION DISTINCT

  -- pharmacy records
  SELECT
    c.hadm_id,
    ph.starttime AS starttime
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN cohort c USING(hadm_id)
  WHERE
    ph.starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(ph.medication, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide)')
    AND ph.starttime BETWEEN c.admittime AND c.dischtime

  UNION DISTINCT

  -- eMAR administrations (charttime used as start)
  SELECT
    c.hadm_id,
    e.charttime AS starttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN cohort c USING(hadm_id)
  WHERE
    e.charttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(e.medication, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide)')
    AND e.charttime BETWEEN c.admittime AND c.dischtime
),

flags AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM meds m
        WHERE m.hadm_id = c.hadm_id
          AND m.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
      ) THEN 1 ELSE 0
    END AS started_in_first_24h,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM meds m
        WHERE m.hadm_id = c.hadm_id
          AND m.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
          AND m.starttime <= c.dischtime
      ) THEN 1 ELSE 0
    END AS started_in_final_12h
  FROM cohort c
)

SELECT
  ROUND(100.0 * SUM(started_in_first_24h) / COUNT(1), 2) AS pct_started_first_24h,
  ROUND(100.0 * SUM(started_in_final_12h) / COUNT(1), 2) AS pct_started_final_12h
FROM flags;