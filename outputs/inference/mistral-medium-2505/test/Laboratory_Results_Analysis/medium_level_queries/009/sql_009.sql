WITH female_admissions AS (
  -- Get female patients aged 59-69 at admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),

hs_tnt_measurements AS (
  -- Get hs-TnT measurements with their charttime
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    -- Filter for hs-TnT using label (more reliable)
    d.label LIKE '%hs-TnT%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),

first_hs_tnt AS (
  -- Get the first hs-TnT measurement per admission
  SELECT
    h.subject_id,
    h.hadm_id,
    h.valuenum AS first_hs_tnt_value
  FROM
    hs_tnt_measurements h
  WHERE
    h.measurement_rank = 1
    AND h.valuenum > 0.014
)

-- Calculate percentiles and min/max of first hs-TnT values
SELECT
  PERCENTILE_CONT(f.first_hs_tnt_value, 0.25) AS percentile_25,
  PERCENTILE_CONT(f.first_hs_tnt_value, 0.5) AS percentile_50,
  PERCENTILE_CONT(f.first_hs_tnt_value, 0.75) AS percentile_75,
  MIN(f.first_hs_tnt_value) AS min_value,
  MAX(f.first_hs_tnt_value) AS max_value
FROM
  first_hs_tnt f
JOIN
  female_admissions fa
ON
  f.subject_id = fa.subject_id AND f.hadm_id = fa.hadm_id;