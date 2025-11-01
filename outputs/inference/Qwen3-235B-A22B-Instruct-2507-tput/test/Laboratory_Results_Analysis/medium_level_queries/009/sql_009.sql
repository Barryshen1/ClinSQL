WITH pt_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),
hs_tnt AS (
  SELECT
    la.hadm_id,
    la.charttime,
    la.valuenum,
    ROW_NUMBER() OVER (PARTITION BY la.hadm_id ORDER BY la.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents la
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON la.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t high sensitive%'
    AND la.valuenum IS NOT NULL
),
first_hs_tnt AS (
  SELECT
    pt.hadm_id,
    pt.age_at_admit,
    hs.valuenum AS first_hs_tnt_value
  FROM pt_age pt
  INNER JOIN hs_tnt hs
    ON pt.hadm_id = hs.hadm_id
  WHERE pt.gender = 'F'
    AND pt.age_at_admit BETWEEN 59 AND 69
    AND hs.rn = 1
    AND hs.valuenum > 0.014
)
SELECT
  ROUND(APPROX_PERCENTILE(first_hs_tnt_value, 0.25), 4) AS percentile_25,
  ROUND(APPROX_PERCENTILE(first_hs_tnt_value, 0.50), 4) AS percentile_50,
  ROUND(APPROX_PERCENTILE(first_hs_tnt_value, 0.75), 4) AS percentile_75,
  MIN(first_hs_tnt_value) AS min_value,
  MAX(first_hs_tnt_value) AS max_value
FROM first_hs_tnt;