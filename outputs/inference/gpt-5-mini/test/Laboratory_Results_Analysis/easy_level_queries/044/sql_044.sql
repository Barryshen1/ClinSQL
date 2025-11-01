WITH ischemic_adms AS (
  -- Male, age 94 admissions that have a diagnosis consistent with ischemic stroke
  SELECT DISTINCT a.hadm_id, a.subject_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 94
    -- text-based heuristic for ischemic stroke / cerebral infarction / CVA
    AND (
      (LOWER(d.long_title) LIKE '%ischemic%' AND (LOWER(d.long_title) LIKE '%stroke%' OR LOWER(d.long_title) LIKE '%infarct%' OR LOWER(d.long_title) LIKE '%cerebral%'))
      OR LOWER(d.long_title) LIKE '%cerebral infarction%'
      OR LOWER(d.long_title) LIKE '%cva%'
    )
),

glucose_on_discharge AS (
  -- For each ischemic admission, find glucose labs on the discharge day (<= dischtime) and take the last one
  SELECT
    g.hadm_id,
    g.subject_id,
    g.charttime,
    g.valuenum AS glucose,
    ROW_NUMBER() OVER (PARTITION BY g.hadm_id ORDER BY g.charttime DESC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS g
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON g.itemid = li.itemid
  JOIN ischemic_adms AS ia
    ON g.hadm_id = ia.hadm_id
  WHERE g.charttime IS NOT NULL
    -- same calendar day as discharge
    AND DATE(g.charttime) = DATE(ia.dischtime)
    -- not after discharge time
    AND g.charttime <= ia.dischtime
    -- glucose tests (label-based); require numeric value
    AND LOWER(li.label) LIKE '%glucose%'
    AND (
      LOWER(COALESCE(li.fluid, '')) LIKE '%serum%'
      OR LOWER(COALESCE(li.fluid, '')) LIKE '%plasma%'
      OR LOWER(COALESCE(li.fluid, '')) LIKE '%blood%'
      OR LOWER(li.label) LIKE '%serum%'
    )
    AND g.valuenum IS NOT NULL
)

-- Compute quartiles and IQR across one glucose value per admission (the last on discharge day)
SELECT
  q[OFFSET(1)] AS glucose_p25,
  q[OFFSET(3)] AS glucose_p75,
  q[OFFSET(3)] - q[OFFSET(1)] AS glucose_iqr,
  (SELECT COUNT(*) FROM glucose_on_discharge WHERE rn = 1) AS n_admissions_with_glucose
FROM (
  SELECT APPROX_QUANTILES(glucose, 4) AS q
  FROM glucose_on_discharge
  WHERE rn = 1
);