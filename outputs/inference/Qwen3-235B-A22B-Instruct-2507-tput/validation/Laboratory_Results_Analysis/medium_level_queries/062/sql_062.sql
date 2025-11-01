WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    -- Compute age at admission
    (EXTRACT(YEAR FROM a.admittime) + EXTRACT(MONTH FROM a.admittime) / 12.0 + EXTRACT(DAY FROM a.admittime) / 365.25)
    - (p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) + EXTRACT(MONTH FROM a.admittime) / 12.0 + EXTRACT(DAY FROM a.admittime) / 365.25)
        - (p.anchor_year + p.anchor_age) BETWEEN 46 AND 56
),
hstnt_tests AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_days,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY l.charttime) AS rn
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pa.subject_id = l.subject_id AND pa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE (LOWER(d.label) LIKE '%troponin t high sensitivity%'
         OR LOWER(d.label) LIKE '%hs-tnt%'
         OR LOWER(d.label) LIKE '%high sensitivity troponin t%')
    AND l.valuenum IS NOT NULL
),
first_hstnt AS (
  SELECT
    hadm_id,
    los_days,
    valuenum,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum BETWEEN 14 AND 59 THEN 'Borderline'
      WHEN valuenum >= 60 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS interpretation
  FROM hstnt_tests
  WHERE rn = 1
)
SELECT
  interpretation,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM first_hstnt
GROUP BY interpretation
ORDER BY
  CASE interpretation
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;