WITH first_admission AS (
  -- identify the first hospital admission per subject
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM (
    SELECT subject_id, hadm_id, admittime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) AS a
  WHERE a.rn = 1
),
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.deathtime,
    a.hospital_expire_flag,
    -- age at first admission (per MIMIC conventions)
    (p.anchor_age + (EXTRACT(YEAR FROM f.admittime) - p.anchor_year)) AS age_at_first,
    -- in-hospital mortality indicator for that admission
    CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mortality
  FROM first_admission f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = f.subject_id
  WHERE LOWER(p.gender) IN ('m','male')
    AND (p.anchor_age + (EXTRACT(YEAR FROM f.admittime) - p.anchor_year)) BETWEEN 73 AND 83
)
SELECT
  quantiles[OFFSET(1)] AS p25_in_hospital_mortality
FROM (
  SELECT APPROX_QUANTILES(in_hosp_mortality, 4) AS quantiles
  FROM cohort
) AS t;