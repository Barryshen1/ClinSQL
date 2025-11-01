WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 82
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '434%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
        )
    )
),
glucose_measurements AS (
  SELECT 
    ep.hadm_id,
    le.valuenum AS glucose_value,
    ROW_NUMBER() OVER (
      PARTITION BY ep.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ep.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.fluid = 'Blood'
    AND LOWER(dli.label) LIKE '%glucose%'
    AND le.valueuom = 'mg/dL'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ep.admittime
    AND le.charttime <= ep.admittime + INTERVAL '4' HOUR
)
SELECT 
  APPROX_QUANTILES(glucose_value, 1000)[OFFSET(750)] AS glucose_75th_percentile
FROM glucose_measurements
WHERE rn = 1;