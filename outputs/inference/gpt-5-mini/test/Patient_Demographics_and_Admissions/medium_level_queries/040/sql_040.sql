WITH surgical_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    -- must have at least one procedure record in the admission (proxy for "surgical")
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      WHERE pr.hadm_id = a.hadm_id
    )
    -- require valid times to compute LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital_death'
      WHEN discharge_location IS NOT NULL
           AND REGEXP_CONTAINS(UPPER(discharge_location), r'HOME') THEN 'home'
      WHEN discharge_location IS NOT NULL
           AND REGEXP_CONTAINS(UPPER(discharge_location),
             r'(SNF|REHAB|REHABILITATION|LTACH|NURSING|SKILLED|LONG[- ]?TERM|FACILITY)') THEN 'facility'
      ELSE 'other'
    END AS discharge_category
  FROM surgical_inpatients
)

SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_los_ge_7,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_ge_7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS n_los_ge_14,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_ge_14
FROM categorized
-- keep only the three requested strata
WHERE discharge_category IN ('home', 'facility', 'in-hospital_death')
GROUP BY discharge_category
ORDER BY
  -- order meaningful: home, facility, in-hospital_death
  CASE discharge_category
    WHEN 'home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'in-hospital_death' THEN 3
    ELSE 4
  END;