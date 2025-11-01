WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- LOS group: 1-4 days vs 5-8 days
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group,
    -- ICU use: yes if there exists any icustay for this admission, otherwise no
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.subject_id = a.subject_id
          AND icu.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_use,
    -- Radiography/CT count per admission (from ICU procedureevents)
    COALESCE(r.radiography_events, 0) AS radiography_events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN (
    SELECT di.subject_id, di.hadm_id, di.icd_code, di.icd_version, dd.long_title
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dd.icd_code = di.icd_code
     AND dd.icd_version = di.icd_version
  ) AS diag ON diag.subject_id = a.subject_id AND diag.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
  ) icu ON icu.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT pe.hadm_id, COUNT(*) AS radiography_events
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2
      ON pe.itemid = di2.itemid
    WHERE REGEXP_CONTAINS( di2.label, r'(?i)(Radiography|Radiology|X-?Ray|CT)')
    GROUP BY pe.hadm_id
  ) r ON r.hadm_id = a.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 59 AND 69
    AND REGEXP_CONTAINS(diag.long_title, r'(?i)heart\\s*failure')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

-- Part 2: Aggregate percentiles by LOS group and ICU use
SELECT
  los_group,
  icu_use,
  -- p25, p50, p75 percentiles of radiography_counts per admission within the group
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT
    icu_use,
    los_group,
    APPROX_QUANTILES(radiography_events, 4) AS quantiles
  FROM cohort
  WHERE los_group IS NOT NULL
  GROUP BY icu_use, los_group
)
ORDER BY icu_use, los_group;