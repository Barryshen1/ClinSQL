WITH male_acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND (
          d.icd_code = 'I20.0' 
          OR d.icd_code = 'I24.0'
          OR d.icd_code LIKE 'I21.%'
          OR d.icd_code LIKE 'I22.%'
        )
    )
),
troponin_events AS (
  SELECT 
    maa.hadm_id,
    le.valuenum
  FROM male_acs_admissions maa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON maa.hadm_id = le.hadm_id
  WHERE le.itemid IN (50189, 50190, 50191)  -- Troponin I assays
    AND le.valuenum IS NOT NULL
    AND le.charttime >= maa.admittime
    AND le.charttime <= maa.dischtime
),
peak_troponin_per_admission AS (
  SELECT 
    hadm_id,
    MAX(valuenum) AS peak_troponin
  FROM troponin_events
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(peak_troponin, 1000)[OFFSET(750)] AS peak_troponin_75th_percentile
FROM peak_troponin_per_admission;