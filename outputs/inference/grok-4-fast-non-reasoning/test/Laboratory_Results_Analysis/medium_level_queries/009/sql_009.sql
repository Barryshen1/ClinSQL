WITH first_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
    )
),
hs_tnt_items AS (
  SELECT 
    itemid,
    label
  FROM 
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE 
    LOWER(label) LIKE '%troponin t%' 
    AND LOWER(label) LIKE '%hs%'
),
initial_hs_tnt AS (
  SELECT 
    hadm_id,
    valuenum AS initial_valuenum
  FROM (
    SELECT 
      le.hadm_id,
      le.valuenum,
      le.charttime,
      fa.admittime,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN 
      first_admissions fa ON le.hadm_id = fa.hadm_id
    INNER JOIN 
      hs_tnt_items di ON le.itemid = di.itemid
    WHERE 
      le.charttime >= fa.admittime
      AND DATE_DIFF(DATE(le.charttime), DATE(fa.admittime), DAY) <= 1  -- Within first day
      AND le.valuenum IS NOT NULL 
      AND le.valuenum > 0.014
      AND le.valueuom = 'ng/mL'
  ) ranked
  WHERE rn = 1
)
SELECT 
  MIN(initial_valuenum) AS min_hs_tnt,
  APPROX_QUANTILES(initial_valuenum, 4)[OFFSET(1)] AS p25_hs_tnt,
  APPROX_QUANTILES(initial_valuenum, 4)[OFFSET(2)] AS p50_hs_tnt,
  APPROX_QUANTILES(initial_valuenum, 4)[OFFSET(3)] AS p75_hs_tnt,
  MAX(initial_valuenum) AS max_hs_tnt
FROM 
  initial_hs_tnt;