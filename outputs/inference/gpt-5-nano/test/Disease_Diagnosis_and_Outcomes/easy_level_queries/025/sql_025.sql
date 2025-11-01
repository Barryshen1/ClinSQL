WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'm'  -- male
    AND a.dischtime IS NOT NULL
),
age_at_adm AS (
  SELECT
    b.*,
    (CAST(b.anchor_age AS FLOAT64) + (b.adm_year - CAST(b.anchor_year AS INT64))) AS age_at_adm
  FROM base b
),
primary_upper_gi_bleed AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9  AND di.icd_code IN ('578.0','578.1','578.9'))
      OR
      (di.icd_version = 10 AND di.icd_code IN ('K92.0','K92.1','K92.2'))
    )
)
SELECT STDDEV_SAMP(los) AS stddev_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los
  FROM age_at_adm AS a
  JOIN primary_upper_gi_bleed AS g
    ON a.subject_id = g.subject_id AND a.hadm_id = g.hadm_id
  WHERE a.age_at_adm BETWEEN 77 AND 87
) t;