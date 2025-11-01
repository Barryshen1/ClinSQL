WITH
-- Get admissions with ACS diagnoses for male patients aged 64
acs_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 64
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')
),

-- Get troponin measurements
troponin_measurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND (d.label LIKE '%Troponin%' OR d.label LIKE '%TnI%' OR d.label LIKE '%TnT%')
    AND l.valuenum IS NOT NULL
),

-- Calculate peak troponin per admission
peak_troponin AS (
  SELECT
    hadm_id,
    MAX(valuenum) AS peak_troponin
  FROM troponin_measurements
  GROUP BY hadm_id
)

-- Calculate the 75th percentile of peak troponin values
SELECT
  PERCENTILE_CONT(peak_troponin, 0.75) OVER() AS percentile_75_peak_troponin
FROM (SELECT peak_troponin FROM peak_troponin)
LIMIT 1;