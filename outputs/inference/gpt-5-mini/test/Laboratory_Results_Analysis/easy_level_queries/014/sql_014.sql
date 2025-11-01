WITH hemoglobin_items AS (
  -- pick lab itemids that represent hemoglobin (exclude A1c variants)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hemoglobin%'
    AND LOWER(label) NOT LIKE '%a1c%'
    AND LOWER(label) NOT LIKE '%hba1c%'
),

gi_admissions AS (
  -- admissions that have any diagnosis suggesting GI bleeding
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE (
        (LOWER(dd.long_title) LIKE '%gastrointestinal%' AND LOWER(dd.long_title) LIKE '%hemorrhag%')
     OR LOWER(dd.long_title) LIKE '%gastrointestinal bleeding%'
     OR LOWER(dd.long_title) LIKE '%gi bleed%'
     OR LOWER(dd.long_title) LIKE '%melena%'
     OR LOWER(dd.long_title) LIKE '%hematemesis%'
  )
),

discharge_day_hgb AS (
  -- for each eligible admission, pick the last hemoglobin measured on the discharge date (<= dischtime)
  SELECT
    le.hadm_id,
    le.valuenum AS hgb_g_per_dl,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime DESC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hemoglobin_items hi
    ON le.itemid = hi.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  JOIN gi_admissions g
    ON le.hadm_id = g.hadm_id
  WHERE p.anchor_age = 45
    AND p.gender = 'F'
    AND le.valuenum IS NOT NULL
    -- restrict to lab measurements occurring on the discharge date and not after the discharge time
    AND DATE(le.charttime) = DATE(a.dischtime)
    AND le.charttime <= a.dischtime
    -- prefer measurements in g/dL when unit available; allow null units (some rows omit units)
    AND (
         LOWER(IFNULL(le.valueuom, '')) LIKE '%g/dl%'
         OR le.valueuom IS NULL
        )
)
SELECT
  -- approximate 75th percentile of discharge-day hemoglobin (g/dL)
  APPROX_QUANTILES(hgb_g_per_dl, 100)[OFFSET(75)] AS discharge_day_hgb_75th_percentile_g_per_dL,
  COUNT(1) AS admissions_count_used
FROM (
  -- take only the last measurement per admission (rn = 1)
  SELECT hadm_id, hgb_g_per_dl
  FROM discharge_day_hgb
  WHERE rn = 1
) t;