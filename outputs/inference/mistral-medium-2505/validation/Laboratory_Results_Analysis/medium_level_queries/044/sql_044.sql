WITH male_patients_54_64 AS (
  -- Get male patients aged 54-64 at admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission if anchor_age is not available
    CASE
      WHEN p.anchor_age IS NOT NULL THEN p.anchor_age
      ELSE EXTRACT(YEAR FROM a.admittime) - p.anchor_year
    END AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (
      (p.anchor_age BETWEEN 54 AND 64)
      OR
      (EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 54 AND 64)
    )
),

troponin_t_measurements AS (
  -- Get Troponin-T measurements with itemid for Troponin-T
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label LIKE '%Troponin T%'  -- Adjust if the exact label is different
    AND l.valuenum > 0.01
),

first_troponin_t_per_admission AS (
  -- Get the first Troponin-T measurement per admission
  SELECT
    t.subject_id,
    t.hadm_id,
    t.valuenum,
    t.valueuom
  FROM
    troponin_t_measurements t
  WHERE
    t.measurement_rank = 1
)

-- Final aggregation
SELECT
  COUNT(*) AS n,
  AVG(valuenum) AS mean,
  STDDEV(valuenum) AS sd,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max,
  PERCENTILE_DISC(valuenum, 0.5) OVER() AS median,
  PERCENTILE_DISC(valuenum, 0.25) OVER() AS percentile_25,
  PERCENTILE_DISC(valuenum, 0.75) OVER() AS percentile_75
FROM
  first_troponin_t_per_admission f
JOIN
  male_patients_54_64 m
  ON f.subject_id = m.subject_id AND f.hadm_id = m.hadm_id;