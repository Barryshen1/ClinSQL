WITH
-- Get the itemid for hemoglobin
hemoglobin_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Hemoglobin'
),

-- Identify 45-year-old females with GI bleeding
target_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 45
    AND d.icd_code IN ('K92.2') -- GI bleeding ICD-10 code
    AND a.hospital_expire_flag = 0 -- Alive at discharge
),

-- Get the last hemoglobin value on the discharge day
discharge_hemoglobin AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    l.valuenum AS hemoglobin_g_dL
  FROM target_patients t
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON t.hadm_id = l.hadm_id
  JOIN hemoglobin_itemid h
    ON l.itemid = h.itemid
  WHERE
    DATE(l.charttime) = DATE(t.dischtime) -- Same day as discharge
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY l.charttime DESC) = 1 -- Last value of the day
)

-- Compute the 75th percentile
SELECT
  PERCENTILE_CONT(discharge_hemoglobin.hemoglobin_g_dL, 0.75) OVER() AS p75_hemoglobin_g_dL
FROM discharge_hemoglobin
LIMIT 1;